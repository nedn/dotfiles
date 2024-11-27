set -o xtrace 

# bash config
cp .bashrc ~/
# Mac uses this instead of .bashrc
cp .bash_profile ~/

cp .bash_aliases ~/
cp .bash_functions ~/
source ~/.bashrc
# vim config
cp .vimrc ~/
cp -r .vim ~/
# python start up
cp .pythonstartup ~/
# git
cp .gitconfig ~/

# install quickopen
quickopen_dir="$HOME/quickopen"
if  [ ! -d $quickopen_dir ]; then
	echo "quickopen does not exist. Installing.."
	cd ~/
	git clone https://github.com/natduca/quickopen
	cd quickopen
	git submodule update --init --recursive
fi

kitty_config_dir='~/.config/kitty'
if [ -d "$kitty_config_dir" ]; then
  cp kitty.conf $kitty_config_dir
fi

if command -v nvim >/dev/null 2>&1; then
	nvim_config_dir="$HOME/.config/nvim"
	mkdir -p "$nvim_config_dir"
	cp .vimrc "$nvim_config_dir/init.vim"
	echo "Succesfully create init.vim config for neovim!"
fi
