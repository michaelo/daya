#!/bin/bash
version=$(cat VERSION)

rm -rf zig-out
for target in x86_64-windows x86_64-macos x86_64-linux aarch64-windows aarch64-macos aarch64-linux
do
    targetversion=$target-v$version
    echo Building $targetversion
    zig build -Dtarget=$target --prefix-exe-dir $targetversion -Drelease-safe
    cd zig-out

    if [[ "$target" == *"windows"* ]]; then
    echo Generation archive: $targetversion.zip
    zip -r $targetversion.zip $targetversion
    cd ..
    else
    echo Generation archive: $targetversion.tar.gz
    tar -czf $targetversion.tar.gz $targetversion
    cd ..
    fi
done
