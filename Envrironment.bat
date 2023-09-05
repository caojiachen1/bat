@echo off
winget source remove winget
winget source add winget https://mirrors.ustc.edu.cn/winget-source
git config --global http.proxy "http://127.0.0.1:7890"
git config --global https.proxy "https://127.0.0.1:7890"