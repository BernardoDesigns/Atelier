[ -s ../stub.log ] || { echo "stubs not invoked"; exit 1; }
# Nothing new outside .atelier/: the repo holds only the fixture's own files.
find . -type f -not -path './.atelier/*' -not -path './.git/*' | sort > ../files.txt
printf '%s\n' ./node_modules/.bin/eslint ./node_modules/.bin/tsc ./src/a.tsx | sort | diff - ../files.txt
