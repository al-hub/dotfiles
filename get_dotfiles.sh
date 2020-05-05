cp ~/.bashrc . 
cp ~/.vimrc .
cp ~/.Xresources .
cp ~/.tmux.conf .

git add . 
git commit -m "update `date +'%Y-%m-%d %H:%M:%S'`"
git push

