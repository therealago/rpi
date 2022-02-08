function apt-updater {
	sudo apt-get update &&
	sudo apt-get dist-upgrade -Vy &&
	sudo apt-get autoremove -y &&
	sudo apt-get autoclean &&
	sudo apt-get clean
}

alias lla='ls -lhAv --group-directories-first'
alias refresh='source ~/.bashrc'
