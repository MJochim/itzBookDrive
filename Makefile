default:
	@echo "No compiling needed"

install: 
	install -m755 -t /usr/local/bin bookdrive.pl upload.sh remote-postprocessing.sh

