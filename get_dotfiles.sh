cp ~/.bashrc . 
mkdir -p dotfiles
cp ~/.vimrc dotfiles/vimrc
cp ~/.myrc dotfiles/myrc
cp ~/.Xresources dotfiles/Xresources
cp ~/.tmux.conf dotfiles/tmux.conf

git add . 
git commit -m "update `date +'%Y-%m-%d %H:%M:%S'`"
git push
