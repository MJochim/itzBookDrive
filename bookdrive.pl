#!/usr/bin/perl -w

################################################################################
###                                                                          ###
### Control program for our BookDrive mini                                   ###
###                                                                          ###
### © 2012-2014 Markus Jochim, Herbert Lange, Gebhard Grelczak               ###
###                                                                          ###
###                                                                          ###
### Requires WxPerl, GPhoto2 and ImageMagick and                             ###
### /etc/udev/rules.d/70-persistent-input.rules to detect the USB trigger.   ###
###                                                                          ###
###                                                                          ###
################################################################################

use warnings;
use strict;
use Wx;
use Fcntl;

# Paths to helper programs
my $gphoto2 = "/usr/local/bin/gphoto2-patch";
my $postprocess = "/usr/local/bin/postprocess.sh";
my $uploader = "/usr/local/bin/upload.sh";
my $imageViewer = "eog -w";

### Path where scans are saved (in a sub-directory for each book)
my $path = "/home/it-zentrum/BookDrive/Projekte/";

### Serial numbers of the two cameras
my %serials=("3271c4ab65e8489cb05f87f281a74344" => "LE",  # LEft
             "966ba8da5be64520a0ee4108bce1b88d" => "RI"); # RIght


my $projectTitle = "";
my $thumbnailPath;
my $discardedPath;

my %usbids;


###
my $bookUpsideDown = 0;
my $useHardwareTrigger = 0;
my $page = 1;
my $jpgLeft;
my $jpgRight;
my $bitmapLeft;
my $bitmapRight;
my $filenameLeft="";
my $filenameRight="";
my $trigger;
my $triggerFound;

###############
###          ##
### GUI      ##
###          ##
###############

package BookdriveFrame;
use base 'Wx::Frame';
use Wx qw (:everything);
use Wx::Event qw (:everything);

use File::Basename;

# Hash with all controls (= buttons, input fields, labels etc.) on our window
my %controls = ();

###
#
# The next 100 or so lines only deal with placing the controls on the window and registering event handlers
#
###
sub new {
	# Create window
	my $ref = shift;
	$controls{'self'} = $ref->SUPER::new( undef, -1, "Bücherscan", [415, 102], [550, 870] );


	# Create controls
	$controls{'panel'} = Wx::Panel->new ( $controls{'self'}, -1 );

	$controls{'heading'} = Wx::StaticText->new ( $controls{'panel'},  -1, "Bücher scannen am IT-Zentrum für Sprach- und Literaturwissenschaften\nMit dem BookDrive Mini", 
		[10,10], [-1,-1], wxALIGN_CENTRE);
	MakeBold($controls{'heading'});

	$controls{'auto_or_manual'} = Wx::RadioBox->new ( $controls{'panel'}, -1, "Scan-Auslöser", [10, 60], [-1, -1], ["Automatisch: Wenn der Hebel runter gezogen wird", "Manuell: Auf Knopfdruck"]);
	$controls{'auto_or_manual'}->SetSelection(1);
	$controls{'auto_or_manual'}->Enable($triggerFound);

	$controls{'book_orientation'} = Wx::RadioBox->new ( $controls{'panel'}, -1, "Buch-Ausrichtung", [10, 120], [-1, -1], ["Normal: Linke seite liegt links", "Auf dem Kopf: Linke Seite liegt rechts"]);

	$controls{'book_title_caption'} = Wx::StaticText->new ( $controls{'panel'}, -1, "Buch-Titel: ", [10, 180], [-1, -1] );
	$controls{'book_title'} = Wx::TextCtrl->new ( $controls{'panel'}, -1, "", [$controls{'book_title_caption'}->GetSize()->x + 10, 170], [250, -1] );

	$controls{'first_page_caption'} = Wx::StaticText->new ( $controls{'panel'}, -1, "Erste Seite: ", [10, 210], [-1, -1] );
	$controls{'first_page'} = Wx::TextCtrl->new ( $controls{'panel'}, -1, "1", [$controls{'first_page_caption'}->GetSize()->x + 10, 200], [50, -1] );

	$controls{'start_workflow'} = Wx::Button->new ( $controls{'panel'}, -1, "STARTEN", [420, 210] );


	$controls{'heading_scan'} = Wx::StaticText->new ( $controls{'panel'}, -1, "Arbeitsschritt: Scannen", [10, 250] );
	MakeBold($controls{'heading_scan'});

	$controls{'current_pages_caption'} = Wx::StaticText->new ( $controls{'panel'}, -1, "Einlegen/Umblättern zu den Seiten ", [20, 270] );
	$controls{'current_pages'} = Wx::StaticText->new ( $controls{'panel'}, -1, "1 und 2", [20 + $controls{'current_pages_caption'}->GetSize()->x, 270] );
	MakeBold($controls{'current_pages'});

	$controls{'change_pages_caption'} = Wx::StaticText->new ( $controls{'panel'}, -1, "Oder stattdessen andere Seiten Scannen: ", [20, 300] );
	my $x = $controls{'change_pages_caption'}->GetSize()->x + 20;
	$controls{'change_pages_down'} = Wx::Button->new ( $controls{'panel'}, -1, "<", [ $x, 290 ] );
	$x += $controls{'change_pages_down'}->GetSize()->x + 20;
	$controls{'change_pages_up'} = Wx::Button->new ( $controls{'panel'}, -1, ">", [ $x, 290 ] );

	$controls{'change_pages_down'}->Disable();
	$controls{'change_pages_up'}->Disable();

	### "& " sets up the hotkey alt+space for this buton (indicated as an underlined space behind the button's caption)
	$controls{'trigger'} = Wx::Button->new ( $controls{'panel'}, -1, "Auslösen (Alt+Space) & ", [ 20, 330 ] );
	$controls{'trigger'}->Disable();


	$x = $controls{'change_pages_down'}->GetPosition()->x;
	my $w = 2*$controls{'change_pages_down'}->GetSize()->x + 20;
	$controls{'exit'} = Wx::Button->new ( $controls{'panel'}, -1, "Oder: Fertig, beenden!", [ $x, 330 ], [ $w, -1 ] );


	$controls{'heading_check'} = Wx::StaticText->new ( $controls{'panel'}, -1, "Arbeitsschritt: Überprüfen", [10, 380] );
	MakeBold($controls{'heading_check'});
	$controls{'saved_in'} = Wx::StaticText->new ( $controls{'panel'}, -1, "Scans werden gespeichert in: " . $path, [20, 400] );
	$controls{'filename_left'} = Wx::StaticText->new ( $controls{'panel'}, -1, "", [20, 420] );
	$controls{'filename_right'} = Wx::StaticText->new ( $controls{'panel'}, -1, "", [280, 420] );

	$controls{'imagepanel_left'} = Wx::Panel->new ( $controls{'panel'}, -1, [20, 440], [250, 375] );
	$controls{'imagepanel_right'} = Wx::Panel->new ( $controls{'panel'}, -1, [280, 440], [250, 375] );
	$controls{'imageclick_description'} = Wx::StaticText->new ( $controls{'panel'}, -1, "Scan in Originalgröße anzeigen: Die Vorschau anklicken.\nÖffnet einen externen Betrachter (Eye of Gnome).", [20, 825] );
	

	## Prepare preview images
	
	$jpgLeft = Wx::Image->new();
	$jpgRight = Wx::Image->new();
	Wx::InitAllImageHandlers();
	$bitmapLeft = wxNullBitmap;
	$bitmapRight = wxNullBitmap;




	## Register Events
	EVT_BUTTON ( $controls{'self'}, $controls{'start_workflow'}, \&OnClickStartWorkflow );
	EVT_BUTTON ( $controls{'self'}, $controls{'change_pages_down'}, \&OnClickPagesDown );
	EVT_BUTTON ( $controls{'self'}, $controls{'change_pages_up'}, \&OnClickPagesUp );
	EVT_BUTTON ( $controls{'self'}, $controls{'trigger'}, \&OnTrigger );
	EVT_BUTTON ( $controls{'self'}, $controls{'exit'}, \&OnClickClose );
	EVT_LEFT_UP ( $controls{'imagepanel_left'}, \&OnClickLeftImage );
	EVT_LEFT_UP ( $controls{'imagepanel_right'}, \&OnClickRightImage );

	EVT_PAINT( $controls{'imagepanel_left'}, \&OnPaintLeftImage );
	EVT_PAINT( $controls{'imagepanel_right'}, \&OnPaintRightImage );
	
	EVT_CLOSE ( $controls{'self'}, \&OnClose );

	EVT_TIMER ( $controls{'self'}, -1, \&OnTimer );

	#EVT_CHAR_HOOK ( $controls{'self'}, \&OnChar );



	## Create a timer used to poll the hardware trigger
	$controls{'timer'} = Wx::Timer->new($controls{'self'});


	## Returns a reference to the newly created window
	return $controls{'self'};
}

## Makes a wxStaticText bold
sub MakeBold {
	my $window = shift;
	my $font = $window->GetFont();
	$font->SetWeight(wxFONTWEIGHT_BOLD);
	$window->SetFont($font);
}



### Event handlers

sub OnTimer {
	## Read trigger device in non-blocking mode
	debug ("timing");
	my $buffer;
	while ( read ( $trigger, $buffer, 144 ) ) {
		debug("triggering by timer");
		OnTrigger(@_);
	}
}

sub OnPaintLeftImage {
	my $dcLeft = Wx::PaintDC->new($controls{'imagepanel_left'});

	$dcLeft->DrawBitmap ( $bitmapLeft, 0, 0, 0 ) if ( $bitmapLeft->IsOk() );
}

sub OnPaintRightImage {
	my $dcRight = Wx::PaintDC->new($controls{'imagepanel_right'});
	$dcRight->DrawBitmap ( $bitmapRight, 0, 0, 0 ) if ( $bitmapRight->IsOk() );
}

sub OnClickLeftImage {
	if ( $filenameLeft ne "" ) {
		## Start external image viewer
		system( $imageViewer . " '$filenameLeft' &" ); 
	}
}

sub OnClickRightImage {
	if ( $filenameRight ne "" ) {
		## Start external image viewer
		system( $imageViewer . " '$filenameRight' &" );
	}
}

sub OnClickClose {
	$controls{'self'}->Close();
}

sub OnClose {
	my ($blah, $event) = @_; 

	if (! $event->CanVeto()) {
		print "Dying\n";
		$controls{'self'}->Destroy();
	} else {
		my $dialog = Wx::MessageDialog->new( $controls{'self'}, "Alle Scans wurden zusammen mit den Thumbnails in ".$path." gespeichert.\n\nAll scans have been saved to ".$path." along with their thumbnails.\n\nBeenden/Exit?", "Beenden?", wxYES_NO | wxNO_DEFAULT );
		if ( $dialog->ShowModal() == wxID_YES ) {
			$controls{'self'}->Destroy();
		} else {
			$event->Veto();
		}
	}
}

sub OnTrigger {
	debug( "Triggering");

	## Colour application window red
	$controls{'panel'}->SetOwnBackgroundColour(wxRED);
	$controls{'panel'}->Update();

	## Disable buttons that must not be pressed during scan
	$controls{'trigger'}->Disable();
	$controls{'change_pages_up'}->Disable();
	$controls{'change_pages_down'}->Disable();

	my ($blah, $event) = @_;
	$event->Skip();

	## Make sure the user sees the buttons disabled
	$controls{'self'}->Update();


	## Make timestamp 
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
	localtime(time);
	$sec  = "0$sec" if ($sec<10);
	$min  = "0$min" if ($min<10);
	$hour = "0$hour" if ($hour<10);
	$mday = "0$mday" if ($mday<10);
	$mon += 1; # Month is in the range 0..11, which is useless for us
	$mon  = "0".($mon+1) if ($mon<9);
	$year += 1900;
	my $timestamp = $year."_".$mon."_".$mday."-".$hour."_".$min."_".$sec;


	## Determine page numbers of right and left photo
	## $bookUpsideDown indicates on which side the lower page number is found (set by the user)
	my $left = $page;
	my $right = $page;
	if ( $bookUpsideDown ) {
		$left++;
	} else {
		$right++;
	}


	my $stringLeft = $left."-".$timestamp.".jpg";
	my $stringRight = $right."-".$timestamp.".jpg";
	$filenameLeft = $path.$stringLeft;
	$filenameRight = $path.$stringRight;


	## If there already are scans of the current pages, move them to the "discarded" subdir

	## Find previous scans of left page
	my @files;

	if ( index($path, " ") != -1 ) {
		@files = glob "\"${path}${left}-*\"";
	} else {
		@files = glob "${path}${left}-*";
	}

	foreach my $file ( @files ) {
		debug ("Discarding old file: $file");
		system ("mv --backup=numbered '$file' '".$discardedPath.$left.".jpg'");
	}

	## Find previous scans of right page
	@files = glob "${path}${right}-*";
	foreach my $file ( @files ) {
		debug ("Discarding old file: $file");
		system ("mv --backup=numbered '$file' '".$discardedPath.$right.".jpg'");
	}


	## Capture and process photos (rotation, thumbnail creation)

	# Test case: copy some random photos to the right location (as if they had just been scanned)
	#system("cp /mnt/I/50\\ Software/93\\ Skripte/BookDrive/test-bilder/$left-*.jpg \"$filenameLeft\"");
	#system("cp /mnt/I/50\\ Software/93\\ Skripte/BookDrive/test-bilder/$right-*.jpg \"$filenameRight\"");

	# Control cameras via gphoto2
	# NB: the LEFT camera shoots the RIGHT image
	# With jpegtran the two images are rotated correctly (takes about .3 seconds per photo)
	# 'convert' creates the thumbnails
	# Using this shell syntax, both images are processed in parallel, but the system call only returns control when BOTH
	# are finished
	debug ("Capturing and processing photos (gphoto \| jpegtran\; convert)");
	system("
		(
		$gphoto2 --port $usbids{LE} --capture-image-and-download --stdout 2>/dev/null | jpegtran -rotate 90 -trim > \"$filenameRight\";
		convert \"$filenameRight\" -resize 250 \"".$thumbnailPath.$stringRight."\"
		) &
		(
		$gphoto2 --port $usbids{RI} --capture-image-and-download --stdout 2>/dev/null | jpegtran -rotate 270 -trim > \"$filenameLeft\";
		convert \"$filenameLeft\" -resize 250 \"".$thumbnailPath.$stringLeft."\"
		) &
		wait
		"
	);

	## Upload the newly taken images to the postprocessing machine
	system ($uploader . " \"". $projectTitle . "\" ". " \"" . $filenameLeft . "\" \"" . $filenameRight . "\" &");


	## Load and display the captured images
	debug ("Loading thumbnails");
	$controls{'filename_left'}->SetLabel(basename($filenameLeft));
	$controls{'filename_right'}->SetLabel(basename($filenameRight));

	if ( ! $jpgLeft->LoadFile( $thumbnailPath.$stringLeft, wxBITMAP_TYPE_JPEG ) ) {
		$jpgLeft->Destroy();
	}

	if ( ! $jpgRight->LoadFile ( $thumbnailPath.$stringRight, wxBITMAP_TYPE_JPEG ) ) {
		$jpgRight->Destroy();
	}

	$bitmapLeft = Wx::Bitmap->new($jpgLeft);
	$bitmapRight = Wx::Bitmap->new($jpgRight);


	
	## Remove last images from the windows
	$controls{'imagepanel_left'}->Refresh();
	$controls{'imagepanel_left'}->Update();
	$controls{'imagepanel_right'}->Refresh();
	$controls{'imagepanel_right'}->Update();
	
	## Draw new images
	my $dcLeft = Wx::ClientDC->new($controls{'imagepanel_left'});
	my $dcRight = Wx::ClientDC->new($controls{'imagepanel_right'});
	$dcLeft->DrawBitmap ( $bitmapLeft, 0, 0, 0 );
	$dcRight->DrawBitmap ( $bitmapRight, 0, 0, 0 );



	## Increase page number
	OnClickPagesUp();

	## Re-enable trigger button
	$controls{'trigger'}->Enable();
	$controls{'change_pages_up'}->Enable();
	$controls{'change_pages_down'}->Enable();
	$controls{'trigger'}->SetFocus();
	
	## Remove red background
	$controls{'panel'}->SetOwnBackgroundColour(wxNullColour);

	debug ("Done");
}


sub OnChar {
	my ( $self, $event ) = @_;

	if ( $event->GetKeyCode() == WXK_F5 ) {
		if ( $controls{'change_pages_up'}->IsEnabled() ) {
			OnClickPagesUp();
		}
	}

	$event->Skip();
}

sub OnClickStartWorkflow {
	
	## Disable all controls that must not be changed after "starting the workflow"
	$controls{'start_workflow'}->Disable();
	$controls{'first_page'}->Disable();
	$controls{'book_title'}->Disable();
	$controls{'auto_or_manual'}->Disable();
	$controls{'book_orientation'}->Disable();
	
	
	## Read on what page the user wants to start
	$page = $controls {'first_page'}->GetValue();
	if ( $page !~ /^-{0,1}[0-9]{1,}$/ ) {
		$controls{'first_page'}->SetValue("UNGÜLTIG-NEHME 1");
		$page = 1;
	}
	$controls{'current_pages'}->SetLabel( $page . " und " . ($page+1) );


	## Read whether the book is upside down
	$bookUpsideDown = $controls{'book_orientation'}->GetSelection();


	## Read whether the user wants to control scanning using a screen button or a hardware trigger
	$useHardwareTrigger = ($controls{'auto_or_manual'}->GetSelection() == 0);
	if ($useHardwareTrigger) {
		$controls{'timer'}->Start(500);
	}


	## Determine path to save the scans to
	my $title = $controls{'book_title'}->GetValue();
	$title =~ tr/\\\/:/_/;
	$path .= $title . "/";
	$projectTitle = $title;
	$thumbnailPath = $path."thumbnails/";
	$discardedPath = $path."verworfen/";
	$controls{'saved_in'}->SetLabel ( "Scans werden gespeichert in: " . $path );
	mkdir ($path, 0755);
	mkdir ($thumbnailPath, 0755);
	mkdir ($discardedPath, 0755);


	## Start postprocessing script that will do the scantailoring and (possibly) OCR
	## during the scan workflow
	system ($postprocess . " \"" . $title . "\" &");

	
	## Enable controls that are only allowed once the workflow has been started
	$controls{'trigger'}->Enable();
	$controls{'change_pages_down'}->Enable();
	$controls{'change_pages_up'}->Enable();
}

## Go one double page back in scanning images (a. k. a. repeat the previous scan because I've fucked it up)
sub OnClickPagesDown {
	$page -= 2;
	$controls{'current_pages'}->SetLabel ( $page . " und " . ($page+1) );
}

## Skip one double page in scanning
sub OnClickPagesUp {
	$page += 2;
	$controls{'current_pages'}->SetLabel ( $page . " und " . ($page+1) );
}


## Debug method
sub debug {
	system ("echo \$(date +%S.%N): '@_'");
}


###
### Create the WxWidgets 'application' that encapsulates the window created above
###

package BookdriveApp;
use base 'Wx::App';

sub OnInit {
	my $frame = BookdriveFrame->new;
	$frame->Show( 1 );
}



###############
###          ##
### Here     ##
### ends the ##
### GUI part ##
###          ##
###############


package main;


# USB-Ids für die Kameras auslesen
my $temp=`$gphoto2 --auto-detect | grep Canon`;
my @kameras=split /\n/, $temp;

# Den USB-Ids mit Hilfe der Kamera-Seriennummern die Seiten zuweisen
foreach my $k (@kameras)
{
	if ($k=~/(usb:\d{3},\d{3})/) {
		my $usbid=$1;
		$temp=`$gphoto2 --summary --port $usbid`;
		if ($temp=~/Seriennummer: ([0-9a-f]{32})/) {
			my $serial=$1;
			$usbids{$serials{$serial}}=$usbid;
		}
	}
}


## Open hardware trigger device
if ( ! sysopen ( $trigger, "/dev/input/trigger", O_NONBLOCK|O_RDONLY) ) {
	print ("Konnte Hardware-Trigger nicht öffnen: $!\n");
	$triggerFound = 0;
} else {
	$triggerFound = 1;
}



## Start the WxWidgets app
my $app = BookdriveApp->new;
$app->MainLoop;

