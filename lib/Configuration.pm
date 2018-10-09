#!/usr/bin/perl

package Configuration;

use strict;
use warnings;

use Encode qw/from_to/;

use LWP::Simple qw/get/;
use Win32::GUI qw(MB_ICONQUESTION MB_ICONINFORMATION);
use threads;
use threads::shared;

use LOG;
use Time;
use Color;

my $url =<<EOF
https://raw.githubusercontent.com/redwyz/autobid_config/master/etc/config/config.ini
EOF
;

my $config_dir = '.\etc\config';
mkdir $config_dir unless -d $config_dir;

#print get("https://raw.githubusercontent.com/redwyz/autobid_config/master/etc/config/config.ini");

sub new {
    my ($class) = @_;
    my $config = {};
    
    $config->{local_time} = 0;
	$config->{bid1} = 1;
	$config->{set_hour1} = 11;
	$config->{set_min1} = 29;
	$config->{set_sec1} = 30;
	$config->{add_price1} = 300;
	
	$config->{bid2} = 1;
	$config->{set_hour2} = 11;
	$config->{set_min2} = 29;
	$config->{set_sec2} = 45;
	$config->{add_price2} = 1000;
	
	$config->{deadline} = 55;
	$config->{deadline_delay} = 500;
	
	$config->{advance_submit_price} = 100;
	$config->{delay} = 500;
	
	$config->{local_time} = 0;
	$config->{enlarge_code} = 1;
	
	$config->{auto_delay} = 0;
	$config->{check_deadline} = 0;
	
	$config->{f3} = 300;
	$config->{f4} = 400;
	$config->{f5} = 500;
	$config->{f6} = 600;
	$config->{f7} = 700;
	$config->{f8} = 'AUTO';
	$config->{add_price_40} = 1100;
	$config->{add_price_41} = 1100;
	$config->{add_price_42} = 1100;
	$config->{add_price_43} = 1000;
	$config->{add_price_44} = 1000;
	$config->{add_price_45} = 900;
	$config->{add_price_46} = 800;
	$config->{add_price_47} = 800;
	$config->{add_price_48} = 700;
	$config->{add_price_49} = 700;
	$config->{add_price_50} = 700;
	$config->{add_price_51} = 700;
	$config->{add_price_52} = 600;
	$config->{add_price_53} = 600;
	$config->{add_price_54} = 500;
	$config->{add_price_55} = 500;
	$config->{add_price_56} = 400;
	$config->{add_price_57} = 300;
	
    bless $config, __PACKAGE__;
}

sub trim {
    my $string = shift;
    if ($string) {
        $string =~ s/^\s+//;
        $string =~ s/\s+$//;
    }
    return $string;
}

sub set {
	my $config = shift;
	my $key = shift;
	my $value = shift;

	lock $config;
	$config->{$key} = $value;
}

sub load_config {
	
    my $config = shift;
    lock $config;
    
    my @config_files = glob("$config_dir\\*.ini");

    if (@config_files < 1 && $url) {
        $config->{content} = get($url);
        unless ($config->{content}) {
            Win32::GUI::MessageBox(0, "加载配置文件失败！", "提示", MB_ICONINFORMATION|0);
            return;
            #exit;
        }
    } elsif (@config_files == 1) {
        $config->{config_file} = $config_files[0];
    } else {
	    # if more than one config file
	    my $desk = Win32::GUI::GetDesktopWindow();
	    my $dw = Win32::GUI::Width($desk);
	    my $dh = Win32::GUI::Height($desk);
	    my $w = 400;
	    my $h = 200;
	    
	    my $Window;
	    $Window = new Win32::GUI::DialogBox(
	        -name   => "Config",                    # Window name (important for OEM event)
	        -title  => "选择配置文件",              # Title window
	        -pos    => [($dw - $w) / 2, ($dh - $h) / 2],                   # Default position
	        -size   => [$w, $h],                    # Default size
	        -dialogui => 1,                         # Enable keyboard navigation like DialogBox
	        -class => 'my_Win32GUI_class_with_changed_icon',
	        -onTerminate => sub {
	            my $index = $Window->Combo->GetCurSel();
	            if ($index < 0) {
	                $Window->MessageBox("请选择配置文件！", "提示", MB_ICONINFORMATION|0);
	                return 0;
	            }
	            return -1;
	        },
	        -helpbutton => 0
	    );
	
	    $Window->AddCombobox(
	        -name => 'Combo',
	        -pos => [100,50],
	        -size => [200,20],
	        -dropdownlist => 1,
	        -onChange => sub { 
	            my $index = $Window->Combo->GetCurSel();
	            return if ($index < 0);
	            $config->{config_file} = $config_files[$index];
	            Win32::GUI::DestroyWindow($Window);
	            return -1;
	        }
	    );
	    $Window->Combo->AddString($_) for @config_files;
	    $Window->Show();
	    Win32::GUI::Dialog();   	
    }
    
    my @config_lines;
    
    # remote config
    if ($config->{content}) {
        write_log("远程加载配置");
        @config_lines = split "\n", $config->{content};
        delete $config->{content};
    }
    elsif ($config->{config_file}) {
        write_log("加载本地配置文件： [$config->{config_file}]");
        my $fh;
        unless (open $fh, $config->{config_file}) {
            write_log("Can not open config file: $!\n");
            exit;
        }
        @config_lines = <$fh>;
        close $fh;
        delete $config->{config_file};
    }
    
    foreach my $line (@config_lines) {
        chomp $line;
        next if (!$line or $line =~ /^\s*\#/ or $line =~ /^\s*$/);
        my ($key, $value) = map {trim($_);} split /\s*=\s*/, $line, 2;
        
        if ($key =~ /bid_url/ || $key eq 'version' || $key =~ /pattern/ || $key =~ /code_cover/) {
            $config->{$key} = $value;
        }
        elsif ($key =~ /color$/) {
        	my $color = Color->new(split /\s*,\s*/, $value);
        	$config->{$key} = shared_clone($color);
        }
        elsif ($key =~ /time$/) {
        	my $time = Time->new_by_string($value);
        	$config->{$key} = shared_clone($time);
        }
        else {
        	$config->{$key} = $value;
        }

    }
    return $config;
}

1;