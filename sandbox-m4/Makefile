path:
	@echo ">>>  BSD m4, no options (errors expected)"
	-m4  path.m4
	@echo
	@echo ">>>  GNU m4, no options (errors expected)"
	-gm4 path.m4
	@echo
	@echo ">>>  BSD m4, -I option"
	m4  -I incl path.m4
	@echo
	@echo ">>>  GNU m4, -I option"
	gm4 -I incl path.m4
	@echo
	@echo ">>>  BSD m4, -I,-d options"
	m4  -I incl -dp path.m4
	@echo
	@echo ">>>  GNU m4, -I,-d options"
	gm4 -I incl -dp path.m4
	@echo
	@echo ">>>  GNU m4, -I,-d++ options"
	gm4 -I incl -dpfl path.m4
