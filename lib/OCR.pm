#!/usr/bin/perl

package OCR;

use strict;
use warnings;

use Win32::Process;
use Imager::Screenshot qw/screenshot/;

use threads;
use threads::shared;

use LOG;

my $convert_cmd = qq(.\\plugin\\ImageMagick\\convert.exe);
my $tesseract_cmd = qq(.\\plugin\\Tesseract-OCR\\tesseract.exe);

$ENV{TESSDATA_PREFIX} = qq(.\\plugin\\Tesseract-OCR\\);

our $tmp_path = '.\tmp';

mkdir $tmp_path unless -d $tmp_path;

eval {
	opendir(DH, $tmp_path);
	
	while( defined (my $file = readdir(DH)) ) {
	    
	    if ($file =~ /^confirm_\d{6}/) {
	    	unlink "$tmp_path\\$file";
	    }
	}
	
	close DH;
};

sub new {
	
	my ($class, $name) = @_;
	
	my $ocr = {
		name => $name,
		file => "$tmp_path\\$name" . '.bmp',
		result => "$tmp_path\\$name"
	};
	
	bless $ocr, __PACKAGE__;
}

sub snapshot {

	my $ocr = shift;
	my $rect = shift;

	my $left = $rect->{left} + $main::ax_abs_left;
	my $right = $rect->{right} + $main::ax_abs_left;
	my $top = $rect->{top} + $main::ax_abs_top;
	my $bottom = $rect->{bottom} + $main::ax_abs_top;

	$ocr->{image} = screenshot(left => $left, right => $right, top => $top, bottom => $bottom);
		
	return $ocr;
}

sub grey {

	my $ocr = shift;
	$ocr->{image} = $ocr->{image}->convert(preset => 'gray') if $ocr->{image};
	return $ocr;
}

sub scale {

	my $ocr = shift;
	my $scale_factor = shift;

	$ocr->{image} = $ocr->{image}->scale(scalefactor => $scale_factor) if $ocr->{image};

	return $ocr;
}

sub write_file {

	my $ocr = shift;
	my $file = shift;
	if ($ocr->{image}) {
		$ocr->{image}->write(file => $file ? $file : $ocr->{file}, type => 'bmp' ) or write_log("Write file error: $ocr->{image}->{ERRSTR}");
	}
	return $ocr;
}

sub convert_png {
	
	my $ocr = shift;

	my $png_file = "$tmp_path\\$ocr->{name}" . '.png';
	
	my $command = "$convert_cmd $ocr->{file} $png_file";

	my $process;

	Win32::Process::Create($process, $convert_cmd, $command, 1, CREATE_NO_WINDOW|HIGH_PRIORITY_CLASS, ".")
            or write_log("could not spawn child process: " . Win32::FormatMessage(Win32::GetLastError()) . "\n");
	
	$process->Wait(INFINITE);

	$ocr->{png_file} = $png_file;

	return $ocr;
}

sub concat_image {
	my @files = @_;
	my $out_put_file = "$tmp_path\\splash.bmp";
	
	my $command = "$convert_cmd -append " . join ' ', @files;
	$command .= " $out_put_file";

	my $process;

	Win32::Process::Create($process, $convert_cmd, $command, 1, CREATE_NO_WINDOW|HIGH_PRIORITY_CLASS, ".")
            or write_log("could not spawn child process: " . Win32::FormatMessage(Win32::GetLastError()) . "\n");
	
	$process->Wait(INFINITE);

	return $out_put_file;	
	
}


sub convert {

	my $ocr = shift;
	#my ($scale, $mono) = @_;
	my $scale = shift;
	my $mono = shift;

	$mono = $mono ? "-monochrome" : '';
	$scale = $scale ? "-scale $scale%" : '';

	system "$convert_cmd -compress none -depth 8 -alpha off -colorspace gray $scale $mono $ocr->{file} $ocr->{file}";

	return $ocr;
}


sub recgonize {

	my ($ocr, $lang) = @_;
	
	my $process;
	my $command = "$tesseract_cmd -psm 6 -l $lang $ocr->{file} $ocr->{result} quiet";
	
	$command .= ' digits' if ($lang eq 'num' or $lang eq 'id' or $lang eq 'my_price');

	Win32::Process::Create($process, $tesseract_cmd, $command, 1, CREATE_NO_WINDOW|HIGH_PRIORITY_CLASS, ".")
            or write_log("Could not spawn child process: " . Win32::FormatMessage(Win32::GetLastError()) . "\n");
	
	#$ProcessObj->SetPriorityClass($class)
	$process->Wait(INFINITE);

	# get string
	open FILE, "<", "$ocr->{result}.txt";
	my $text = <FILE>;
	chomp $text if ($text);
	close FILE;

	return $text;
}


1;