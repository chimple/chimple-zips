rm -rf public/*
mkdir -p public

for zip in *.zip; do
  NAME="$(basename "$zip" .zip)"
  mkdir -p "public/$NAME"
  unzip -o "$zip" -d "public/$NAME"
done
