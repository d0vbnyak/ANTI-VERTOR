#!/bin/bash
# Локальная проверка в стиле Вертера (Школа 21):
# компиляция, clang-format и проверка утечек памяти для каждого .c файла.
# Использование: ./check.sh [папка]   (по умолчанию текущая)

DIR="${1:-.}"
CFLAGS="-Wall -Werror -Wextra -std=c11 -g"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; }

# Ищем .clang-format: в папке, в materials/linters или используем Google-стиль
if   [ -f "$DIR/.clang-format" ]; then STYLE="file"
elif [ -f "materials/linters/.clang-format" ]; then
    cp materials/linters/.clang-format "$DIR/.clang-format"; STYLE="file"
else STYLE="{BasedOnStyle: Google}"
fi

# Чем проверять память: valgrind (Linux) или leaks (macOS)
if command -v valgrind >/dev/null; then MEM="valgrind"
elif command -v leaks >/dev/null; then MEM="leaks"
else MEM=""; echo -e "${YELLOW}valgrind/leaks не найдены, проверка памяти пропущена${NC}"
fi

total=0; passed=0

shopt -s nullglob
files=("$DIR"/*.c)
if [ ${#files[@]} -eq 0 ]; then echo "Нет .c файлов в $DIR"; exit 1; fi

for f in "${files[@]}"; do
    total=$((total + 1))
    exe="${f%.c}"
    file_ok=1
    echo -e "\n${YELLOW}=== $(basename "$f") ===${NC}"

    # 1. Стиль
    if clang-format --style="$STYLE" -n --Werror "$f" 2>/dev/null; then
        ok "clang-format"
    else
        fail "clang-format (исправить: clang-format -i $f)"
        clang-format --style="$STYLE" -n "$f" 2>&1 | head -n 10
        file_ok=0
    fi

    # 2. Компиляция
    if gcc $CFLAGS "$f" -o "$exe" 2>/tmp/gcc_err.txt; then
        ok "компиляция"
    else
        fail "компиляция"
        cat /tmp/gcc_err.txt
        echo -e "  ${RED}Итог: FAIL${NC}"
        continue
    fi

    # 3. Утечки памяти (stdin пустой, лимит 10 секунд)
    if [ "$MEM" = "valgrind" ]; then
        if timeout 10 valgrind --leak-check=full --show-leak-kinds=all \
            --errors-for-leak-kinds=all --error-exitcode=42 -q \
            "$exe" </dev/null >/dev/null 2>/tmp/vg.txt; then
            ok "valgrind"
        else
            fail "valgrind"; head -n 20 /tmp/vg.txt; file_ok=0
        fi
    elif [ "$MEM" = "leaks" ]; then
        if leaks -quiet -atExit -- "$exe" </dev/null >/tmp/vg.txt 2>&1; then
            ok "leaks"
        else
            fail "leaks"; grep -A5 "leaks for" /tmp/vg.txt; file_ok=0
        fi
    fi

    if [ $file_ok -eq 1 ]; then
        passed=$((passed + 1)); echo -e "  ${GREEN}Итог: OK${NC}"
    else
        echo -e "  ${RED}Итог: FAIL${NC}"
    fi
done

echo -e "\n${YELLOW}Пройдено: $passed / $total${NC}"
[ $passed -eq $total ]
