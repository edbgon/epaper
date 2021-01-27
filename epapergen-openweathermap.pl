#!/usr/bin/perl

use Image::Magick;
use LWP::Simple;
use DateTime;
use Text::Wrap;
use CGI;
use JSON qw( decode_json );

use DBI;

$q = new CGI;
my $volt = $q->param('volt');
my $format = $q->param('format');

$| = 1; # Turn off stdout buffer

my %apikeys;
open(IN, "apikeys.conf");
while(<IN>) {
	chomp($_);
	my @info = split("\t", $_);
	$apikeys{"$info[0]"} = $info[1];
}
close IN;

# If modification time of the XML is not 10 minutes ago or more, use the cached version
my $lasttime = 0;

if(-e "forecast-openweathermap.json") {
	$lasttime = (stat("forecast-openweathermap.json"))[9];
}
else {
	$lasttime = 9999;
}

if (time - $lasttime > 600) {
	my $url = "https://api.openweathermap.org/data/2.5/onecall?lat=60.3&lon=5.338&appid=" . $apikeys{forecast};
	my $file = 'forecast-openweathermap.json';
	getstore($url, $file);
}

$lasttime = 0;
if (-e "xc.info") {
	$lasttime = (stat("xc.info"))[9];
}
else {
	$lasttime = 9999;
}

if (time - $lasttime > 1800) {
        my $url = "https://openexchangerates.org/api/latest.json?app_id=" . $apikeys{exchange} . "&base=USD&symbols=NOK";
        my $file = "xc.info";
        getstore($url, $file);
}

$lasttime = 0;
if (-e "btc.info") { $lasttime = (stat("btc.info"))[9]; }
if (time - $lasttime > 1800) {
        my $url = "https://blockchain.info/ticker";
        my $file = "btc.info";
        getstore($url, $file);
}

my %beaufort = 	(
	'0'	=> '',
	'0.5'	=> '',
	'1.5'	=> '',
	'3.3'	=> '',
	'5.5'	=> '',
	'7.9'	=> '',
	'10.7'	=> '',
	'13.8'	=> '',
	'17.1'	=> '',
	'20.7'	=> '',
	'24.4'	=> '',
	'28.4'	=> '',
	'32.6'	=> ''
);

my %directions = (
	'0'		=> 'N',
	'11.25'		=> 'NNE',
	'33.75'		=> 'NE',
	'56.25'		=> 'ENE',
	'78.75'		=> 'E',
	'101.25'	=> 'ESE',	
	'123.75'	=> 'SE',
	'146.25'	=> 'SSE',
	'168.75'	=> 'S',
	'191.25'	=> 'SSW',
	'213.75'	=> 'SW',
	'236.25'	=> 'WSW',
	'258.75'	=> 'W',
	'281.25'	=> 'WNW',
	'303.75'	=> 'NW',
	'326.25'	=> 'NNW',
	'348.75'	=> 'N'	
);

# Parse JSON
open(JSON, 'forecast-openweathermap.json');
my $json = join("", <JSON>);
close JSON;

$json = decode_json($json);
my (@symbols, @temperatures, @mintemps, @maxtemps, @types, @winds, @press, @windir, @precip);

# Sunrise and sunset times
my @rise = localtime($json->{'current'}->{'sunrise'});
my @set = localtime($json->{'current'}->{'sunset'});
my $rise = sprintf("%02d", $rise[2]) . ":" . sprintf("%02d", $rise[1]);
my $set = sprintf("%02d", $set[2]) . ":" . sprintf("%02d", $set[1]);

for(@{$json->{'daily'}}) {
	my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($_->{'dt'});
	$temperatures[$mday] 	= int($_->{'temp'}->{'day'} - 273.15) . "\xB0";
	$mintemps[$mday] 	= int($_->{'temp'}->{'min'} - 273.15) . "\xB0";
	$maxtemps[$mday] 	= int($_->{'temp'}->{'max'} - 273.15) . "\xB0";
	$symbol[$mday] 		= $_->{'weather'}[0]->{'icon'};
	$types[$mday]		= ucfirst($_->{'weather'}[0]->{'description'});
	$winds[$mday]		= $_->{'wind_speed'};
	$press[$mday]		= $_->{'pressure'};
	$windir[$mday]		= $_->{'wind_deg'};
	$precip[$mday]		= 0.0 + $_->{'rain'};

	my $windscale = "";
	foreach my $key (sort {$a <=> $b} keys %beaufort) {
		if($winds[$mday] > $key) {
			$windscale = $beaufort{$key};
		}
	}
	$winds[$mday] = $windscale;

	my $direction = "";
	foreach my $key (sort {$a <=> $b} keys %directions) {
		if($windir[$mday] > $key) {
			$direction = $directions{$key};
		}
	}
	$windir[$mday] = $direction;
}

# What time is it now?
my $dt = DateTime->now(time_zone => 'Europe/Oslo');
my $time = $dt->strftime('%Y-%m-%d %T');

# Reads out exchange rate information
open(IN,"xc.info");
my $xc = join("",<IN>);
close IN;
chomp($xc);
my @xc = split(": ", $xc);
$xc = $xc[-1];
$xc =~ /.*?([\d]{1,2}\.[\d]{1,3}).*?/;
$xc = $1;

# Reads out bitcoin exchange rates
open(IN,"btc.info");
my $btc = join("",<IN>);
close IN;
$btc =~ /.*?"USD".*?"last" : ([\d]*\.[\d]{1,2}).*?/gi;
$btc = $1;

# Open font data and extract symbol translation for weather data from yr.no
my %fontdata;
open(IN,"fontdata.info");
for(<IN>) {
	chomp $_;
	my @data = split(" ",$_);
	$fontdata{$data[0]} = $data[1];
}
close IN;

# Create a new white image (ePaper is monochrome only, so be careful with anti-aliased stuff)
my($image, $imagesm, $x);
$image = Image::Magick->new(size=>'640x384');
$image->ReadImage('canvas:white');
$image->Set(antialias=>'False');

# Beginning place for text y variable
my $texty = 155;
my $imaged = Image::Magick->new();

#Put in temperatures
for(my $t = 0; $t < 5; $t++) {
	
	my $ldt = DateTime->now(time_zone => 'Europe/Oslo');
	$ldt->add(days => $t);
	$ldt = $ldt->day();

	#Write weather symbol
	$x = $image->Annotate(font=>'weathericons-regular-webfont.ttf', pointsize=>76, antialias=>'false',
		fill=>'black', text=>$fontdata{$symbol[$ldt]}, align=>'Center', x=> 64 + 128*$t, y=>84);

	#Write temperature
	$x = $image->Annotate(font=>'OpenSans-Bold.ttf', pointsize=>46, antialias=>'false',
		fill=>'black', text=>$temperatures[$ldt], align=>'Center', x=> 54 + 128*$t, y=>$texty);
	$x = $image->Annotate(font=>'tamsyn-webfont.ttf', pointsize=>14, antialias=>'false',
		fill=>'black', text=>$mintemps[$ldt], align=>'Center', x=> 102 + 128*$t, y=>$texty);	
	$x = $image->Annotate(font=>'tamsyn-webfont.ttf', pointsize=>14, antialias=>'false',
		fill=>'black', text=>$maxtemps[$ldt], align=>'Center', x=> 102 + 128*$t, y=>$texty - 24);	

	$Text::Wrap::columns = 12;
	$types[$ldt] = wrap('', '', $types[$ldt]);

	#Write day of the week name
	$x = $image->Annotate(font=>'OpenSans-Bold.ttf', pointsize=>19, antialias=>'false',
		fill=>'black', text=>DateTime->now()->add(days=>$t)->day_name, 
		align=>'Center', x=> 64 + 128*$t, y=>$texty+20);

	#Write weather conditions
	$x = $image->Annotate(font=>'tamsyn-webfont.ttf', pointsize=>14, antialias=>'false',
		fill=>'black', text=>$types[$ldt], 
		align=>'Center', x=> 64 + 128*$t, y=>$texty+40);

	#Write beaufort winds
	$x = $image->Annotate(font=>'weathericons-regular-webfont.ttf', pointsize=>54, antialias=>'false',
		fill=>'black', text=>$winds[$ldt], 
		align=>'Center', x=> 64 + 128*$t, y=>$texty+125);

	#Write wind directions
	$x = $image->Annotate(font=>'tamsyn-webfont.ttf', pointsize=>14, antialias=>'false',
		fill=>'black', text=>$windir[$ldt], 
		align=>'Center', x=> 64 + 128*$t - 15, y=>$texty+113);	

	#Write precipitation amounts
	$x = $image->Annotate(font=>'tamsyn-webfont.ttf', pointsize=>14, antialias=>'false',
		fill=>'black', text=>$precip[$ldt] . " mm", 
		align=>'Center', x=> 64 + 128*$t, y=>$texty+140);

	#Write pressures
	$x = $image->Annotate(font=>'tamsyn-webfont.ttf', pointsize=>14, antialias=>'false',
		fill=>'black', text=>$press[$ldt] . " hPa", 
		align=>'Center', x=> 64 + 128*$t, y=>$texty+155);

}

# Draw border
$x = $image->Draw(primitive=>'Rectangle', fill=>'none', stroke=>'black', strokewidth=>2, points=>'0, 0, 639, 383');

# Text for finance and sunrise info
my $usdnok = "USD/NOK: $xc, USD/BTC: $btc, Sunrise at $rise, sunset at $set.";
$x = $image->Annotate(font=>'tamsyn-webfont.ttf', pointsize=>14, antialias=>'false',
	fill=>'black', text=> $usdnok, 
	gravity=>'South', y=>28);

# Last updated time
$x = $image->Annotate(font=>'tamsyn-webfont.ttf', pointsize=>14, antialias=>'false',
	fill=>'black', text=> "Last updated: $time, Battery: $volt V", 
	gravity=>'South', y=>15);

# Last line (not used)
$x = $image->Annotate(font=>'tamsyn-webfont.ttf', pointsize=>14, antialias=>'false',
	fill=>'black', text=> "", 
	gravity=>'South', y=>3);

# Little fun things, weathericons will let you see them in nano of all things
$x = $image->Annotate(font=>'weathericons-regular-webfont.ttf', pointsize=>40, antialias=>'false',
	fill=>'black', text=> "                                          ", 
	gravity=>'South', y=>0);

$image->Write('epaper.png'); # Output for testing, shows latest generated image written out to PNG file

# Log voltage of battery into grafana database
if($volt > 0) {
        # MySQL database configurations
        my $dsn = "DBI:mysql:home";
        my $username = "bobris";
        my $password = 'jambo123';

        # connect to MySQL database
        my %attr = (PrintError=>0,RaiseError=>1 );
        my $dbh = DBI->connect($dsn,$username,$password,\%attr);

        # insert data into the links table
        my $sql = "INSERT IGNORE INTO epaper(time, voltage) VALUES(now(),?)";

        my $stmt = $dbh->prepare($sql);

        $stmt->execute($volt);

        $stmt->finish();
        # disconnect from the MySQL database
        $dbh->disconnect();
}

# Returns pbm only if asked nicely since most browsers can't show pbm files
my $str;
if($format eq 'pbm') { $str = 'pbm:-'; $ftype = "pbm"; }
else { $str = 'png:-'; $ftype="png"; }

# http headers and file output direct to stream
print "Content-Type: image/$ftype\nContent-Disposition: inline; filename=\"epaper.$ftype\"\n\n"; # For electric imp
binmode STDOUT;
$x = $image->Write($str);
