default:
	@echo "No compiling needed"

install: 
	install -d /usr/local/bin
	install -d /usr/local/share/applications
	install -t /usr/local/bin bookdrive.pl upload.sh remote-postprocessing.sh
	install -m644 itzbookdrive.desktop /usr/local/share/applications/

