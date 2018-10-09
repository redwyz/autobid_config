#!/usr/bin/perl

package BID;

use strict;
use warnings;

use OCR;
use LOG;
use Time;
use Color;
use Rectangle;
use Point;

use Imager;
use Imager::Color;

use threads;
use threads::shared;

use Win32::GuiTest qw(:ALL);

sub new {
    my ($class, $config, $coordinates) = @_;
    my $bid = {
        config => $config, 
        coordinates => $coordinates,
    };
    bless $bid, __PACKAGE__;
}

sub get_time {
	
	my $bid = shift;
	my $time = shift;
	
	if (defined $time) {
		if ($time->{sec} >= 60) {
			$time->{sec} %= 60;
			$time->{min}++;
			if ($time->{min} >= 60) {
				$time->{min} %= 60;
				$time->{hour}++;
			}
		}
        return Time->new($time->{hour}, $time->{min}, $time->{sec});
	}
	
    my ($sec, $min, $hour) = localtime time;
    
    return Time->new($hour, $min, $sec);
	
}

sub parse_time {
	
	my $bid = shift;
    my $ocr = OCR->new('time');
    my $rect = $bid->{coordinates}->{'time'};
    
    my $t = $ocr->snapshot($rect)->scale(5)->write_file()->recgonize('num') || '';
	
	undef $ocr;
	
    $t =~ s/\s*//g;
    
    return Time->new_by_string($t);

}

sub parse_current_price_time {
	
	my $bid = shift;
	my $moni = shift || '';
    my $ocr = OCR->new('current_price_time' . $moni);
    my $rect = $bid->{coordinates}->{'current_price_time' . $moni};
    
    my $t = $ocr->snapshot($rect)->scale(5)->write_file()->recgonize('num') || '';
	
	undef $ocr;
	
    $t =~ s/\s*//g;
    
    my $time;
    eval {
    	$time = Time->new_by_string($t);
    };
    
    $time = undef if $@;
    
    return $time;

}

sub get_current_price {
    
    my $bid = shift;
    my $ocr = OCR->new('current_price');
	
	my $rect = $bid->{coordinates}->{'current_price'};
    my $price = $ocr->snapshot($rect)->scale(5)->write_file()->recgonize('num') || 0;

    $price =~ s/\s//g;
    $price =~ s/\D//g;
	
    undef $ocr;

    return $price;
}

sub get_add_300 {
    
    my $bid = shift;

	my $write_file = shift;
	my $ocr = OCR->new('add_300');
	my $rect = $bid->{coordinates}->{'add_300'};
	$ocr->snapshot($rect);
	$ocr->write_file() if $write_file;

	my $found = find_color($ocr->{image}, $bid->{config}->{add_300_color}, 800);
	undef $ocr;
	
	return $found;
}

sub is_confirm_button_available {

	my $bid = shift;
	my $write_file = shift;
	my $ocr = OCR->new('confirm_button_area');
	my $config = $main::config;
	my $rect = $bid->{coordinates}->{'confirm_button_area'};
	$ocr->snapshot($rect)->write_file();
	
	my $found = $ocr->recgonize('eng') || undef;
	undef $ocr;
	
	return $found;    
}

sub save_confirm_dialog {
	my $bid = shift;
	my $time = shift;
	
	my $ocr = OCR->new("confirm_$time");
	my $config = $main::config;
	my $rect = $bid->{coordinates}->{'confirm_dialog_box'};
	$ocr->snapshot($rect)->write_file();
	undef $ocr;
}

sub get_bid_id {
	my $bid = shift;
	my $config = $main::config;
	
	my $ocr = OCR->new('bid_id');
	my $rect = $bid->{coordinates}->{'bid_id'};
	my $id = $ocr->snapshot($rect)->write_file()->recgonize('id') || '';
	undef $ocr;
	$id =~ s/\s*//g;
	#write_log("投标号: $id");
	return $id;
}


sub is_code_load {
	#my ($bid, $img, $refresh_count_ref) = @_;
	my $bid = shift;
	my $img = shift;
	
	my $config = $bid->{config};
	my $count_blue = 0;
	
    foreach my $y (0..$img->getheight() -1) {
        foreach my $x (0..$img->getwidth() - 1) {
            my ($r, $g, $b, $a) = $img->getpixel(x=>$x, y=>$y)->rgba();
            if ($r > 200 && $g < 100 && $b < 100) {
            	$bid->{is_code_load} = 1;
            	return
            }
            elsif (abs($r - $config->{refresh_button_color}->{r}) < 10 && abs($g - $config->{refresh_button_color}->{g}) < 10 && abs($b - $config->{refresh_button_color}->{b}) < 10) {
               if (++$count_blue > 300) {
                    if ($bid->is_bid_window_open()) {
                    	$bid->click_refresh_code();
                    	$bid->{refresh_count}++;
                    	select undef, undef, undef, .5;
                    }
                    return;
               }
            }
        }
    }		
}

sub get_code {
    #my ($bid, $refresh_count_ref) = @_;
    my $bid = shift;
    my $refresh_count_ref = shift;
    my $ocr = OCR->new('code');
    my $file = $ocr->{file};
    
    my $rect = $bid->{coordinates}->{'code'};
    $ocr->snapshot($rect)->write_file();
    
    $bid->is_code_load($ocr->{image}) if $bid->{refresh_count} < $bid->{config}->{refresh_code_count};
    
    undef $ocr;
    
    return $file;
}


sub get_my_price {

    my $bid = shift;
    
    my $ocr = OCR->new('my_price');
	my $rect = $bid->{coordinates}->{'my_price'};
    my $price = $ocr->snapshot($rect)->scale(2)->write_file()->recgonize('my_price') || 0;

    $price =~ s/\s*//g;

    if ($price =~ /^1/) {
        $price = substr $price, 0, 6
    } else {
        $price = substr $price, 0, 5
    }
    
    $price =~ s/\D//g;

    $price = (int ($price / 100)) * 100;
    
    $price = 0 if $price < 10000;

    write_log("我的自定义出价: $price") if defined $price && $price > 0;

    return $price;
}


sub fill_price {
    my $bid = shift;
    my $price = shift;
    
    my $point = $bid->{coordinates}->{'price_entry'};
    my ($mouse_x, $mouse_y) = move_mouse($point);
    
    Win32::GUI::ClipCursor($mouse_x, $mouse_y, $mouse_x, $mouse_y);
                    
    SendMouse('{LeftClick}');
    SendMouse('{LeftClick}');
    
    Win32::GuiTest::SendKeys("^a$price", 10);
    
    threads->yield();
    
    Win32::GUI::DoEvents();
    
    select undef, undef, undef, .25;
        
    Win32::GUI::ClipCursor();
        
    write_log("填写价格: $price");
}


sub click_submit_price {

    my $bid = shift;
    my $point = $bid->{coordinates}->{'submit_price_button'};
    my ($mouse_x, $mouse_y) = move_mouse($point);
    
    Win32::GUI::ClipCursor($mouse_x, $mouse_y, $mouse_x, $mouse_y);
    
    SendMouse("{LeftClick}");
    
    Win32::GUI::ClipCursor();
    
    write_log("点击出价");
}

sub click_refresh_code {

    my $bid = shift;
	my $point = $bid->{coordinates}->{'refresh_code_button'};
    
    my ($mouse_x, $mouse_y) = move_mouse($point);
    
    Win32::GUI::ClipCursor($mouse_x, $mouse_y, $mouse_x, $mouse_y);
    
    SendMouse("{LeftClick}");
    
    Win32::GUI::ClipCursor();
    
    $bid->click_code_entry();
    
    write_log("刷新验证码");
}

sub click_code_entry {
    my $bid = shift;
    my $point = $bid->{coordinates}->{'code_entry'};
    
    move_mouse($point);
    SendMouse("{LeftClick}");
}

sub clear_code_entry {
    my $bid = shift;
    
    $bid->click_code_entry();
    SendMouse("{LeftClick}");
    
    Win32::GuiTest::SendKeys('^a');

    Win32::GuiTest::SendKeys('{DELETE}');
    
    write_log("清空验证码输入框"); 	
}


sub click_submit_code {

    my $bid = shift;
    my $test = shift;
    my $point = $bid->{coordinates}->{'submit_code_button'};
    
    my ($mouse_x, $mouse_y) = move_mouse($point);
    
    Win32::GUI::ClipCursor($mouse_x, $mouse_y, $mouse_x, $mouse_y);
    
    unless ($test) {
    	SendMouse("{LeftClick}");
    }
    
    Win32::GUI::ClipCursor();
}

sub click_cancel {
    my $bid = shift;
    my $test = shift;
    my $point = $bid->{coordinates}->{'cancel_button'};
    
    my ($mouse_x, $mouse_y) = move_mouse($point);
    
    Win32::GUI::ClipCursor($mouse_x, $mouse_y, $mouse_x, $mouse_y);
    
    SendMouse("{LeftClick}") unless $test;
    
    Win32::GUI::ClipCursor();
    
    write_log("点击取消");
    return $bid;
}


sub click_confirm {

    my $bid = shift;
    my $config = $main::config;
	my $point = $bid->{coordinates}->{'confirm_button'};
    
    my ($mouse_x, $mouse_y) = move_mouse($point);
    
    Win32::GUI::ClipCursor($mouse_x, $mouse_y, $mouse_x, $mouse_y);
    
    SendMouse("{LeftClick}");
	
	Win32::GUI::ClipCursor();
	#write_log("点击确认");
    return $bid;

}


sub move_mouse {
    
    my $point = shift;
    
    my $x = $point->{x} + $main::ax_abs_left;
    my $y = $point->{y} + $main::ax_abs_top;
                    
    MouseMoveAbsPix($x, $y);
	
	return ($x, $y);    
}

# capture the screenshot
sub capture_ss {
	my $bid = shift;
	my ($left, $right, $top, $bottom) = @_;

	my $ocr = OCR->new('ss');
	my $rect = Rectangle->new($left, $right, $top, $bottom);
	$ocr->snapshot($rect)->write_file()->convert_png();
	
	return $ocr->{png_file};
}

sub is_bid_window_open {
	my $bid = shift;
	my $write_file = shift;
	my $ocr = OCR->new('my_price_bg_color');
	my $rect = $bid->{coordinates}->{'my_price_bg_color'};
	$ocr->snapshot($rect);
	$ocr->write_file() if $write_file;
	
	my $found = find_color($ocr->{image}, $bid->{config}->{my_price_bg_color}, 10);
	undef $ocr;
	
	return $found;	
}

sub is_bid_end {
	
	my $bid = shift;
	my $ocr = OCR->new('time');
	my $rect = $bid->{coordinates}->{'time'};
	$ocr->snapshot($rect);
	
	return find_color($ocr->{image}, $bid->{config}->{time_color}, 5) ? 0 : 1;
	
}

sub find_color {
	my $img = shift;
	my $color = shift;
	my $min = shift;
	
	return 0 unless $img;
	
	my $count = 0;
	
	foreach my $y (1..$img->getheight() - 1) {
        foreach my $x (1..$img->getwidth() - 1) {
            my ($r, $g, $b, $a) = $img->getpixel(x=>$x, y=>$y)->rgba;
			if (abs($r - $color->{r}) < 10 && abs($g - $color->{g}) < 10 && abs($b - $color->{b}) < 10) {
               if (++$count > $min) {
               		return 1;
               }
            }
        }
	}
	return 0;
}

1;