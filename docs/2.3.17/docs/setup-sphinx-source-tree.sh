#!/usr/bin/env bash
# Copyright (c) 2022 Digital Asset (Switzerland) GmbH and/or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

set -eou pipefail

DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

cd "$DIR"

RELEASE_TAG=$(jq -r '.daml' ../LATEST)
CANTON_RELEASE_TAG=$(jq -r '.canton' ../LATEST)
DOWNLOAD_DIR=$DIR/workdir/downloads
SPHINX_DIR=$DIR/workdir/build/source

prefix=$(jq -r '.prefix' ../LATEST)

mkdir -p $SPHINX_DIR/source/canton
tar xf $DOWNLOAD_DIR/sphinx-source-tree-$RELEASE_TAG.tar.gz -C $SPHINX_DIR --strip-components=1
if [ -d $SPHINX_DIR/theme ]; then
  rm -rf $SPHINX_DIR/theme
fi
(
  cd $DIR/../../../theme
  nix-shell shell.nix --pure --run './build.sh'
  cp -r . $SPHINX_DIR/theme
)
tar xf $DOWNLOAD_DIR/canton-docs-$CANTON_RELEASE_TAG.tar.gz -C $SPHINX_DIR/source/canton

cp $SPHINX_DIR/source/canton/exts/canton_enterprise_only.py $SPHINX_DIR/configs/static/

# Rewrite absolute references.
find $SPHINX_DIR/source/canton -type f -print0 | while IFS= read -r -d '' file
do
    sed -i 's|include:: /substitution.hrst|include:: /canton/substitution.hrst|g ; s|image:: /images|image:: /canton/images|g' $file
    sed -i "s|__VERSION__|$prefix|g" $file
done
sed -i '/^  concepts$/d' $SPHINX_DIR/source/canton/tutorials/tutorials.rst

# Drop Canton’s index in favor of our own.
rm $SPHINX_DIR/source/canton/index.rst

declare -A sphinx_targets=( [html]=html [pdf]=latex )

sed -i "s/'sphinx.ext.extlinks',$/'sphinx.ext.extlinks','canton_enterprise_only','sphinx.ext.todo',/g" $SPHINX_DIR/configs/html/conf.py
sed -i "s/'sphinx.ext.extlinks'$/'sphinx.ext.extlinks','canton_enterprise_only','sphinx.ext.todo'/g" $SPHINX_DIR/configs/pdf/conf.py

# We rename the PDF so need to update the link.
sed -i "s/DigitalAssetSDK\\.pdf/DamlEnterprise$prefix.pdf/" $SPHINX_DIR/theme/da_theme/layout.html

# Setting version number
for file in pdf html; do
    for var in version release; do
        sed -i "s|$var = u'.*'|$var = u'$prefix'|" $SPHINX_DIR/configs/$file/conf.py
    done
done

(
cd $DIR/overwrite
for f in $(find . -type f); do
    target=$SPHINX_DIR/source/$f
    mkdir -p $(dirname $target)
    cp $f $target
done
)

# Insert research page into the architecture toc

sed -i '21a\ \ research' $SPHINX_DIR/source/canton/architecture/architecture.rst

# Title page on the PDF
sed -i "s|Version : .*|Version : $prefix|" $SPHINX_DIR/configs/pdf/conf.py
