if [[ $EUID -eq 0 ]]; then
	export PS1="\[\033[31m\]\u\[\033[m\]@\[\033[32m\]\h:\[\033[33;1m\]\W\[\033[m\]# "
else
	export PS1="\[\033[36m\]\u\[\033[m\]@\[\033[32m\]\h:\[\033[33;1m\]\W\[\033[m\]> "
fi

alias lwh='/usr/local/bin/listhosts'
alias lh='/usr/local/bin/listhosts'

alias configckan="sudo nano /etc/ckan/default/production.ini"

