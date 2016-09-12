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
cd ~/
git clone https://github.com/natduca/quickopen
cd quickopen
git submodule update --init --recursive
