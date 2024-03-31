#!/bin/bash

# Перейти в папку Docker
cd /home/new_load/

# Перебор файлов в папке Docker и выполнение команды sed для каждого файла, исключая файл "sipp"
for file in *; do
  if [[ -f "$file" && "$file" != "sipp" ]]; then
    echo "--->INFO: Удаляются пробелы в файле $file."
    sed -i -e 's/\r$//' "$file"
  fi
done