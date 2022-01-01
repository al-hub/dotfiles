dotfiles
===

This is my personal dotfiles.

command! mycmd : if filetype('%%f') == 'non-file' | execute '!vim %%f' | else | execute '!vim -d %%f %%F' | endif  
nnoremap <cr> :mycmd<cr>

## vim

I'm using [vim-plug][] to manage plugins.  

```
curl -fLo ~/.vim/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

.vimrc
call plug#begin('~/.vim/plugged')
Plug 'scrooloose/nerdtree', { 'on':  'NERDTreeToggle' }
Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' }
call plug#end()


PlugInstall
PlugUpdate
PlugClean

```
[vim-plug]: https://github.com/junegunn/vim-plug
[TBD-vimspector](https://gilee.kr/vimeul-idero-sayonghagi-4-cocro-gangryeoghan-jadongwanseong-gineung-iyonghagi/)  
vim keymap debugging
```
:verbose map <keyword>
```

[debugging](https://github.com/vim-airline/vim-airline/issues/421) : the (slowing) issue on vim-airline extention
```
1. find the all loaded extension 
:AirlineExtensions

2. disabled the extension one by one 
let g:airline_extensions = ['ex1','ex2',.....'extention_name']

3. remove the issued extention as
let g:airline#extensions#searchcount#enabled = 0
at .vimrc

```
Pure Check: vim --clean file.txt  
Profiling [How to see which plugins are making Vim slow?](https://stackoverflow.com/questions/12213597/how-to-see-which-plugins-are-making-vim-slow)
[minivimrc](https://github.com/bling/minivimrc)  

[debugging]()
```
xclip -o -sel c
xclip -o -sel p
```
	
## urxvt

Learning

## tmux

Learning


short cut
default : c+b &, "

reload  
bind, : source-file ~/.tmux.conf  

## rg with fzf
[examples](https://github.com/junegunn/fzf/wiki/Examples)
```shell
#!/bin/bash
# https://github.com/junegunn/fzf

INITIAL_QUERY=$1
#RG_PREFIX="rg --column --line-number --no-heading --color=always --smart-case "
RG_PREFIX="rg -i --files-with-matches --color=always "
FZF_DEFAULT_COMMAND="$RG_PREFIX '$INITIAL_QUERY'" 

RG_POSTFIX="rg --colors 'match:bg:51,51,51' --ignore-case --pretty --context 10 "

FILE=$(fzf --bind "change:reload:$RG_PREFIX {q} || true"\
	--bind 'page-up:preview-up,page-down:preview-down'\
	--bind 'ctrl-u:preview-page-up,ctrl-d:preview-page-down'\
	--bind '?:toggle-preview,alt-w:toggle-preview-wrap'\
	--ansi --height=70% --disabled\
	--query "$INITIAL_QUERY"\
	--preview-window right:70%\
	--preview "bat --color=always {} | $RG_POSTFIX {q} ") && vim $FILE
```

## swap for low memory system
```
sudo swapoff -a
sudo dd if=/dev/zero of=/swapfile bs=1M count=8000
(sudo dd if=/dev/zero of=/swapfile bs=1G count=8)
sudo mkswap /swapfile
sudo swapon /swapfile
grep SwapTotal /proc/meminfo

also you can check it by top
```

## vifm  
vifmrc
```
fileviewer *.[ch],*.[ch]pp,*.[ch]xx env -uCOLORTERM bat --color always --wrap never --pager never %c -p  
fileviewer *.java,*py,*.txt,*.sh,*.bat,*.md,*.xml,Makefile,*.mk,*.gradle env -uCOLORTERM bat --color always --wrap never --pager never %c -p  
fileviewer *.bmp,*.jpg,*.jpeg,*.png,*.gif,*.xpm
         \ imgt %px %py %pw %ph %c
         \ %pc
         \ imgc %px %py %pw %ph

"https://wiki.vifm.info/index.php/Comparing_files
command! cmpinternal compare-cmd %a %S
command! cmp : if expand('%%c') == expand('%%f')
           \ |     echo expand('Comparing %%"c and %%"C:t ...')
           \ |     cmpinternal %c %C
           \ | else
           \ |     echo expand('Comparing files: %%"f ...')
           \ |     cmpinternal %f
           \ | endif

"http://q2a.vifm.info/633/is-it-possible-to-use-f-f-in-a-not-relative-way
command! diff : if paneisat('right') && paneisat('bottom')
            \ |     execute '!vim -d %%C %%c'
            \ | else
            \ |     execute '!vim -d %%c %%C'
            \ | endif
	    
nnoremap <C-w>q :q!<cr>

" https://wiki.vifm.info/index.php/How_to_integrate_fzf_for_fuzzy_finding
command! FZFfind : set noquickview
                \ | let $FZF_PICK = term('find | fzf --height 10 2>/dev/tty')
                \ | if $FZF_PICK != ''
                \ |     execute '!vim' $FZF_PICK
                \ | endif

command! FZFfindFOLDER : set noquickview
                \ | let $FZF_PICK = term('find | fzf --height 10 2>/dev/tty')
                \ | if $FZF_PICK != ''
                \ |     let $FZF_PATH = term('dirname $FZF_PICK') 
                \ |     execute 'cd' $FZF_PATH
                \ | endif

" variation that automatically enters directories
command! FZFlocate : set noquickview
                \ | let $FZF_PICK = term('find | fzf-tmux --height 10 2>/dev/tty')
                \ | if $FZF_PICK != ''
                \ |     execute 'goto' fnameescape($FZF_PICK)
                \ | endif

nnoremap <c-g> :FZFfindFOLDER<cr>
nnoremap <c-f> :FZFfind<cr>


nnoremap <PageDown>  <C-w>w5j<C-w>w
nnoremap <PageUp>    <C-w>w5k<C-w>w

noremap <C-_> :!sh ~/.fzf/bin/fif-vifm.sh <cr>
```

~/.config/vifm/scripts/compare-cmd  
```
#!/bin/bash

if [ $# != 2 ] ; then
    echo 'Expected exactly two arguments'
    exit 1
fi

if [ -f "$1" -a -f "$2" ]; then
    args=
elif [ -d "$1" -a -d "$2" ]; then
    args='-r'
else
    if [ -f "$1" ]; then
        type_of_1='file'
    else
        type_of_1='directory'
    fi
    if [ -f "$2" ]; then
        type_of_2='file'
    else
        type_of_2='directory'
    fi
    echo "Arguments are of different type ($type_of_1/$type_of_2)"
    exit 1
fi

if diff $args "$1" "$2" > /dev/null 2>&1; then
    echo 'Equal'
else
    echo 'Not equal'
fi
```

~/.config/vifm/scripts/imgc  
```
#!/bin/bash

W3MIMGDISPLAY="/usr/lib/w3m/w3mimgdisplay"
FONTH=15 # Size of one terminal row
FONTW=7 # Size of one terminal column

pane_left=$(tmux display-message -p '#{pane_left}')
pane_top=$(tmux display-message -p '#{pane_top}')

X=$1
Y=$2
X=$((X + pane_left))
Y=$((Y + pane_top))
COLUMNS=$3
LINES=$4

x=$((FONTW * X))
y=$((FONTH * Y))

erase="6;$x;$y;$(( FONTW*COLUMNS ));$(( FONTH*LINES ))\n3;"
echo -e "$erase" | $W3MIMGDISPLAY
```

~/.config/vifm/scripts/imgt  
```
#!/bin/bash
W3MIMGDISPLAY="/usr/lib/w3m/w3mimgdisplay"
FONTH=15 # Size of one terminal row
FONTW=7 # Size of one terminal column

pane_left=$(tmux display-message -p '#{pane_left}')
pane_top=$(tmux display-message -p '#{pane_top}')

X=$(($1 + pane_left))
Y=$(($2 + pane_top))
#X=$((X + pane_left))
#Y=$((Y + pane_top))

COLUMNS=$3
LINES=$4
FILENAME=$5

read width height <<< `echo "5;$FILENAME" | $W3MIMGDISPLAY`
if [ -z "$width" -o -z "$height" ]; then
    echo 'Error: Failed to obtain image size.'
    exit 1
fi

x=$((FONTW * X))
y=$((FONTH * Y))

max_width=$((FONTW * COLUMNS))
max_height=$((FONTH * LINES))

if [ "$width" -gt "$max_width" ]; then
    height=$((height * max_width / width))
    width=$max_width
fi
if [ "$height" -gt "$max_height" ]; then
    width=$((width * max_height / height))
    height=$max_height
fi

w3m_command="0;1;$x;$y;$width;$height;;;;;$FILENAME\n4;\n3;"

echo -e "$w3m_command" | $W3MIMGDISPLAY
```
## w3m  
keymap
```
#navigation similar to vimium
#--------------------------------------------------------------------------------------------------------
keymap j UP
keymap k DOWN
keymap f LIST_MENU
keymap J NEXT_TAB
keymap K PREV_TAB
keymap ? HELP
keymap H BACK
keymap t TAB_LINK
keymap x COMMAND "EXTERN 'echo %s >> ~/.w3m/tmp-restore'; CLOSE_TAB"
keymap X COMMAND "EXTERN 'FILE=~/.w3m/tmp-restore; tail -n 1 $FILE > ~/.w3m/tmp; sed -i \"$ d\" $FILE'; TAB_GOTO ~/.w3m/tmp; MARK_URL;NEXT_LINK;GOTO_LINK"
keymap yy EXTERN 'echo %s | xclip -in -selection clipboar'
keymap yx EXTERN_LINK 'printf %s | xclip -i -selection clipboard'
keymap L SHELL "$EDITOR ~/.w3m/tmp-restore"
#--------------------------------------------------------------------------------------------------------


#split windows with tmux as vim
#--------------------------------------------------------------------------------------------------------
keymap o EXTERN_LINK
keymap C-ws COMMAND "SET_OPTION extbrowser='tmux split-window -v w3m %s'; EXTERN" 
keymap C-w_ COMMAND "SET_OPTION extbrowser='tmux split-window -v w3m %s'; EXTERN_LINK" 
keymap C-wv COMMAND "SET_OPTION extbrowser='tmux split-window -h w3m %s'; EXTERN"
keymap C-w| COMMAND "SET_OPTION extbrowser='tmux split-window -h w3m %s'; EXTERN_LINK"
keymap C-wq COMMAND "EXTERN 'FILE=~/.w3m/tmp-restore; echo %s >> $FILE; echo \"$(uniq $FILE | sed \"/^http/!d\")\" > $FILE'; EXIT"
keymap q COMMAND "EXTERN 'FILE=~/.w3m/tmp-restore; echo %s >> $FILE; echo \"$(uniq $FILE | sed \"/^http/!d\")\" > $FILE'; EXIT"
keymap vi COMMAND "EXTERN 'FILE=~/.w3m/tmp-vim; echo %s > $FILE; vim $FILE'"
keymap vv VIEW
keymap O OPTIONS
#--------------------------------------------------------------------------------------------------------


#image toggle
#--------------------------------------------------------------------------------------------------------
keymap i COMMAND "SET_OPTION display_image=toggle; RELOAD"
#--------------------------------------------------------------------------------------------------------


#java script issue
#--------------------------------------------------------------------------------------------------------
keymap pp COMMAND "VIEW; MARK_URL; NEXT_LINK; GOTO_LINK;"
#keymap pp COMMAND "EXTERN 'var=`echo $W3M_URL | sed \"s/blog/m.blog/g\" | sed \"s/http:/https:/g\"`;w3m $var'; EXIT;"
#--------------------------------------------------------------------------------------------------------


#script example
#https://github.com/gotbletu
#https://vitalyparnas.com/tools/
#keymap po COMMAND "READ_SHELL 'readable $W3M_URL -p html-title,html-content > /tmp/readable.html' ; LOAD /tmp/readable.html; DELETE_PREVBUF"
#keymap po COMMAND "READ_SHELL 'var=`echo $W3M_URL | sed \"s/blog/m.blog/g\"`;w3m $var'; "
#keymap po EXTERN "url=%s; w3m $url"
#keymap po SHELL 'w3m $W3M_URL'
#keymap po COMMAND "SHELL 'var=`echo $W3M_URL | sed \"s/blog/m.blog/g\"`;w3m $var'; EXIT;"
```

## newsboat
urls
```
filter:~/.newsboat/filter_google_US.sh:https://trends.google.com/trends/trendingsearches/daily/rss?geo=US
filter:~/.newsboat/filter_google.sh:https://trends.google.com/trends/trendingsearches/daily/rss?geo=KR
https://news.google.com/rss/search?q=%EC%86%8D%EB%B3%B4%20-%EC%BD%94%EB%A1%9C%EB%82%98&hl=ko&gl=KR&ceid=KR%3Ako "~google fast"
http://newssearch.naver.com/search.naver?where=rss&query=속보&field=0&nx_search_query=&nx_and_query=&nx_sub_query=&nx_search_hlquery=&is_dts=0 "~naver fast"
https://www.schengenvisainfo.com/news/feed/
http://feeds.feedburner.com/Clien_hot10_rss "~client 10"
http://feeds.feedburner.com/c_hot50 "~client 50"
https://alltimelegend.net/bbs/rss.php?bo_table=dcbest "~dcbest"
"exec:~/.newsboat/filter_ppomppu.sh money" "~ppomppu money"
"exec:~/.newsboat/filter_ppomppu.sh humor" "~ppomppu humor"
"exec:~/.newsboat/filter_ppomppu.sh stock" "~ppomppu stock"
"exec:~/.newsboat/filter_fmkorea.sh stock" "~fmkorea stock"
#"file:///home-mc/core.choi/.newsboat/fmkorea.xml" "~fmkorea stock"
https://www.dogdrip.net/stock/rss "~dogdrip stock"
http://feeds.feedburner.com/clien_stock "~client stock"
https://statstock.tistory.com/rss "~SB-kim_statics"
"exec:~/.newsboat/filter_naverblog.sh cybermw" "~SB-report1"
"exec:~/.newsboat/filter_naverblog.sh ionia17" "~SB-report2"
"exec:~/.newsboat/filter_naverblog.sh yminsong" "~SB-100x"
"exec:~/.newsboat/filter_naverblog.sh jyt4159" "~SB-value1"
"exec:~/.newsboat/filter_naverblog.sh badajr" "~SB-value2"
"exec:~/.newsboat/filter_naverblog.sh jakojako" "~SB-index"
"exec:~/.newsboat/filter_naverblog.sh tama2020" "~SB-IT"
"exec:~/.newsboat/filter_naverblog.sh yym0202" "~SB-longterm"
"exec:~/.newsboat/filter_naverblog.sh furmea21" "~SB-invert"
"exec:~/.newsboat/filter_naverblog.sh tosoha1" "~SB-basketball"
"exec:~/.newsboat/filter_naverblog.sh haines" "~SB-MZ_20"
"exec:~/.newsboat/filter_naverblog.sh caruspuer" "~SB-JCTV"
"exec:~/.newsboat/filter_naverblog.sh k764676" "~SB-daily_info"
"exec:~/.newsboat/filter_naverblog.sh sungdory" "~SB-daily_spread"
"exec:~/.newsboat/filter_naverblog.sh crush212121" "~SB-analysis"
"exec:~/.newsboat/filter_naverblog.sh realmanreal" "~SB-account"
"exec:~/.newsboat/filter_naverblog.sh luy1978" "~SB-reserv00"
"exec:~/.newsboat/filter_naverblog.sh kmsmir04" "~SB-reserv01"
"exec:~/.newsboat/filter_naverblog.sh jjanjie3" "~SB-reserv02"
"exec:~/.newsboat/filter_naverblog.sh hls2683445" "~SB-reserv03"
"exec:~/.newsboat/filter_naverblog.sh morgoth" "~SB-reserv04"
"exec:~/.newsboat/filter_naverblog.sh sum7788" "~SB-reserv05"
"exec:~/.newsboat/filter_naverblog.sh shinook430" "~SB-old_jeju"
"exec:~/.newsboat/filter_naverblog.sh zzayofactory" "~SB-old_bio"
```

filter
```
#!/bin/bash
#lynx -source "https://www.fmkorea.com/index.php?mid=stock&sort_index=pop&order_type=desc" | sed "s|<\/a>|<\/a>\n|g" | sed '/hotdeal_var8/!d' | sed 's|.*srl=\(.*\)&amp;listStyle.*>\(.*\)<span.*|\1 \2|g' 
id=$1
url="https://www.fmkorea.com/index.php?mid="$1"&sort_index=pop&order_type=desc"
url_link="https://www.fmkorea.com/"

#cat <<EOF
echo '<?xml version="1.0" encoding="UTF-8"?>'
echo '<rss version="2.0">'
echo '\t<channel>'
echo '\t\t<title>fm-stock</title>'
echo '\t\t<link>'$url'</link>'
echo '\t\t<description>direct acess</description>'
#EOF
{
  lynx -source $url | sed "s|<\/a>|<\/a>\n|g" | sed '/hotdeal_var8/!d' |sed 's|\t||g' | sed 's|.*srl=\(.*\)&amp;listStyle.*>\(.*\)<span.*|\t\t<item>\n\t\t\t<title>\2<\/title>\n\t\t\t<link>'$url_link'\1<\/link>\n\t\t\t<description>\2<\/description>\n\t\t<\/item>|g'
  echo '\t</channel>'
  echo '</rss>'
}


#!/bin/bash
url=https://trends.google.com/trends/trendingsearches/daily/rss?geo=KR
#url=$1
#echo $0 >> /tmp/tmp_newsboat.txt
#echo $@ >> /tmp/tmp_newsboat.txt
#echo $url >> /tmp/tmp_newsboat.txt

cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
	<channel>
		<title>google_trends</title>
		<link>$url</link>
		<description>Stable review patches</description>
EOF
{
lynx -source $url | sed '/ht:/!d' | sed 's|ht:news_item_||g' | sed 's|ht:news_||g' | sed 's|snippet|description|g' | sed 's|url|link|g' | sed '/ht:/d' | sed 's|[^&]*;||g' 

  echo '  </channel>'
  echo '</rss>'
}


#!/bin/bash
url=https://trends.google.com/trends/trendingsearches/daily/rss?geo=US
#url=$1

cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
	<channel>
		<title>google_trends-US</title>
		<link>$url</link>
		<description>Stable review patches</description>
EOF
{
lynx -source $url | sed '/ht:/!d' | sed 's|ht:news_item_||g' | sed 's|ht:news_||g' | sed 's|snippet|description|g' | sed 's|url|link|g' | sed '/ht:/d' | sed 's|[^&]*;||g' 

  echo '  </channel>'
  echo '</rss>'
}


#!/bin/bash
id=$1
rss=https://rss.blog.naver.com/

lynx -source $rss$id | sed "s|blog\.|m\.blog\.|g"  


#!/bin/bash
id=$1
rss=https://www.ppomppu.co.kr/rss.php?id=

lynx -source $rss$id | sed "s|http:|https:|g"  
```

## 어려운문제  
tmux상 vim split 을 mouse로 조정 (tmux와 vim이 mouse focus를 2중으로 가져가는 문제)  
vim airline의 buff tab을 mouse로 클릭하여 선택하기 (미구현 문제)  
urxtvt 에 mouse scroll로 fontsize 수정 ( .Xresources의 URxvt keysym 이해 및 .urxvt/ext/resize-font 구조 이해필요  
https://www.reddit.com/r/archlinux/comments/n7n1ah/urxvt_keysym_for_mouse_buttons_singleline/  
https://wiki.archlinux.org/title/Rxvt-unicode  
https://wiki.archlinux.org/title/Rxvt-unicode/Tips_and_tricks  




## ref
- [endeavor but worth](https://www.bugsnag.com/blog/tmux-and-vim)  
[terminal_life](https://black7375.tistory.com/15)  
https://tech.songyunseop.com/post/2017/07/develop-with-vim/  
https://gitlab.com/dwt1/dotfiles/-/tree/master  
https://jdhao.github.io/2018/09/30/tmux_settings_for_vim_users/  
https://github.com/junegunn/dotfiles  
https://github.com/atomantic/dotfiles  
https://velog.io/@wannte/dotfile을-편하게-관리하는-방법with-Bare-Git-repository  
https://github.com/jongmin92/dev-settings  
https://github.com/lesstif/dotfiles  
https://github.com/christoomey/dotfiles  
https://github.com/johngrib/dotfiles  
https://github.com/rr-/dotfiles/tree/master/cfg  

Thanks all!!
