#!/bin/sh
#install dotfiles for debian(ubuntu)

LISTS="vim\
    w3m\
    vifm\
    tmux\
    bat\
    lsd\
    fd"

install_process() 
{

    if [ "$(which $1)" = "" ] || [ "$(which $1)" = "/usr/bin/vim" ]; then
	echo $1 "installing..."
    else
	echo $1 "already installed!!!"
	return 
    fi

    case $1 in
	vim)
	    ver=$(vim --version | head -n 1 | cut -d ' ' -f 5)

	    echo "vim version :" $ver
	    if [ 1 -eq "$(echo "$ver < 8.2" | bc)" ]; then
		sudo add-apt-repository ppa:jonathonf/vim
		sudo apt-get update
		sudo apt-get install vim
	    fi 
	;;
	bat)
	    wget https://github.com/sharkdp/bat/releases/download/v0.18.3/bat_0.18.3_amd64.deb
	    sudo dpkg -i bat_0.18.3_amd64.deb
	;;
	fd)
	    wget https://github.com/sharkdp/fd/releases/download/v8.3.0/fd_8.3.0_amd64.deb
	    sudo dpkg -i fd_8.3.0_amd64.deb
	;;
	lsd)
	    wget https://github.com/Peltoche/lsd/releases/download/0.20.1/lsd_0.20.1_amd64.deb
	    sudo dpkg -i lsd_0.20.1_amd64.deb
	;;
	*)
	    sudo apt-get install $1
	;;
     esac

}

backup_dotfiles()
{
    NOW=`date +"%Y%m%d_%H%M%S"`
    mkdir -p tmp-$NOW
    FILES=`find ~/. -maxdepth 1 -type f`
    for f in $FILES
    do
	cp $f tmp-$NOW/.
    done
}


copy_dotfiles()
{
    cp .myrc ~/.myrc
    cp .vimrc ~/.vimrc
    cp .tmux.conf ~/.tmux.conf
    cp .Xresources ~/.Xresources
  
    #install vim plugin
    curl -fLo ~/.vim/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

    #.bashrc insert  
    source_myrc="source ~/.myrc"
    check=`cat ~/.bashrc | grep "$source_myrc"`
    if [ ! "$check" ]; then
	echo "" >> ~/.bashrc
	echo $source_myrc >> ~/.bashrc
    fi
    source ~/.bashrc

    echo "TIP) :PlugUpdate in you vim"
}

#initial update
sudo apt-get update

#install program
for program in $LISTS; do install_process $program; done

#backup config 
backup_dotfiles


#copy config (forced)
read -p "will you force copy .dotfiles configure files?(y/n) :" yn 
case $yn in
    [Yy]* ) copy_dotfiles ; break;;
    [Nn]* ) exit;;
esac
