#!/bin/sh
git add .
git commit -m "update"
cd /e/source/git/github/java-nio-learn
git checkout master
git pull
git checkout gh-pages
git pull
cd /e/source/git/gitbook/zhangjk/java-nio-learn
gitbook build
yes | cp -rf /e/source/git/gitbook/zhangjk/java-nio-learn/_book/* /e/source/git/github/java-nio-learn/
cd /e/source/git/github/java-nio-learn
git checkout gh-pages
git add -A .
git commit -m "update"
git push
git checkout master
rsync -av --exclude='_book' --exclude='.git' --exclude='node_modules' --exclude='README.md' ../../gitbook/zhangjk/java-nio-learn/ .
git add -A .
git commit -m "update"
git push