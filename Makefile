all:
	@echo "Possible targets are 'lint', 'tags', maybe more"

lint:
	gawk --lint -f m2 /dev/null

tags:
	ctags m2
