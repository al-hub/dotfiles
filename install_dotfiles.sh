#!/bin/sh
#install dotfiles for debian(ubuntu)

LISTS="vim\
    cmake\
    w3m\
    vifm\
    tmux\
    ctags\
    bat\
    lsd\
    fd\
    fzf\
    rg\
    code-minimap\
    shellcheck"

install_process() 
{

    if [ "$(which $1)" = "" ] || [ "$(which $1)" = "/usr/bin/vim" ]; then
	echo $1 "installing..."
    else
	YELLOW='\033[0;33m'
	NC='\033[0m'
	echo "${YELLOW} $1 already installed!!! ${NC}"
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
	fzf)
	    git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
	    ~/.fzf/install
	;;
	rg)
	    curl -LO https://github.com/BurntSushi/ripgrep/releases/download/13.0.0/ripgrep_13.0.0_amd64.deb
	    sudo dpkg -i ripgrep_13.0.0_amd64.deb
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
	code-minimap)
	    wget https://github.com/wfxr/code-minimap/releases/download/v0.6.2/code-minimap_0.6.2_amd64.deb
	    sudo dpkg -i code-minimap_0.6.2_amd64.deb
	;;
	ctags)
	    sudo apt-get install exuberant-ctags
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

    echo "TRY) source ~/.bashrc"
    echo "     :PlugUpdate in you vim"
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
