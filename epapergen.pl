#!/usr/bin/perl

use Image::Magick;
use LWP::Simple;

use DateTime;
use DateTime::Event::Sunrise;

use Date::Parse;
use Text::Wrap;

use CGI;
use JSON qw( decode_json );
use DBI;

# Retrieve GET variables
$q = new CGI;
my $volt = $q->param('volt');
my $format = $q->param('format');

$| = 1; # Turn off stdout buffer so that PBM files are delivered correctly

# Load in API keys externally so I don't accidentally put them on GitHub
my %apikeys;
open(IN, "apikeys.conf");
while(<IN>) {
	chomp($_);
	my @info = split("\t", $_);
	$apikeys{"$info[0]"} = $info[1];
}
close IN;

# If modification time of the XML is not 10 minutes ago or more, use the cached version
# Download JSON from met.no API (used on yr.no)
my $lasttime = 0;
if(-e "forecast.json") {	$lasttime = (stat("forecast.json"))[9]; } else { $lasttime = 9999; }
if (time - $lasttime > 600) {
	my $url = "https://api.met.no/weatherapi/locationforecast/2.0/complete?lat=60.3&lon=5.338";
	my $file = 'forecast.json';
	getstore($url, $file);
}

# Download exchange rate information
$lasttime = 0;
if (-e "xc.info") {	$lasttime = (stat("xc.info"))[9]; } else { $lasttime = 9999; }
if (time - $lasttime > 1800) {
        my $url = "https://openexchangerates.org/api/latest.json?app_id=" . $apikeys{exchange} . "&base=USD&symbols=NOK";
        my $file = "xc.info";
        getstore($url, $file);
}

# Download current Bitcoin price
$lasttime = 0;
if (-e "btc.info") { $lasttime = (stat("btc.info"))[9]; } else { $lasttime = 9999; }
if (time - $lasttime > 1800) {
        my $url = "https://blockchain.info/ticker";
        my $file = "btc.info";
        getstore($url, $file);
}

# Download current aurora forecast
$lasttime = 0;
if (-e "aurora.info") { $lasttime = (stat("aurora.info"))[9]; } else { $lasttime = 9999; }
if (time - $lasttime > 1800) {
        my $url = "https://www.gi.alaska.edu/monitors/aurora-forecast";
        my $res = get($url);

        for(split("\n", $res)) {
        	if($_ =~ /<p hidden id="db-data">/) {
        		$_ =~ s/.*?<p hidden id="db-data">(.*?)<\/p>.*/${1}/g;
        	    open(OUT, ">aurora.info");
        		print OUT $_;
        		close OUT;
        	}
        }
}


# Beaufort scale in weathericons
my %beaufort = 	(
	'0'		=> '',
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

# Directions with degrees as "FROM" direction
my %directions = (
	'0'			=> 'S',
	'11.25'		=> 'SSW',
	'33.75'		=> 'SW',
	'56.25'		=> 'WSW',
	'78.75'		=> 'W',
	'101.25'	=> 'WNW',	
	'123.75'	=> 'NW',
	'146.25'	=> 'NNW',
	'168.75'	=> 'N',
	'191.25'	=> 'NNE',
	'213.75'	=> 'NE',
	'236.25'	=> 'ENE',
	'258.75'	=> 'E',
	'281.25'	=> 'ESE',
	'303.75'	=> 'SE',
	'326.25'	=> 'SSE',
	'348.75'	=> 'S'	
);

# Descriptions for weather from YR API
my %weatherdesc = (
	'clearsky'						=> 'Clear sky',
	'cloudy'						=> 'Cloudy',
	'fair'							=> 'Fair',
	'fog'							=> 'Fog',
	'heavyrain'						=> 'Heavy rain',
	'heavyrainandthunder'			=> 'Heavy rain and thunder',
	'heavyrainshowers'				=> 'Heavy rain showers',
	'heavyrainshowersandthunder'	=> 'Heavy rain showers and thunder',
	'heavysleet'					=> 'Heavy sleet',
	'heavysleetandthunder'			=> 'Heavy sleet and thunder',
	'heavysleetshowers'				=> 'Heavy sleet showers',
	'heavysleetshowersandthunder'	=> 'Heavy sleet showers and thunder',
	'heavysnow'						=> 'Heavy snow',
	'heavysnowandthunder'			=> 'Heavy snow and thunder',
	'heavysnowshowers'				=> 'Heavy snow showers',
	'heavysnowshowersandthunder'	=> 'Heavy snow showers and thunder',
	'lightrain'						=> 'Light rain',
	'lightrainandthunder'			=> 'Light rain and thunder',
	'lightrainshowers'				=> 'Light rain showers',
	'lightrainshowersandthunder'	=> 'Light rain showers and thunder',
	'lightsleet'					=> 'Light sleet',
	'lightsleetandthunder'			=> 'Light sleet and thunder',
	'lightsleetshowers'				=> 'Light sleet showers',
	'lightsnow'						=> 'Light snow',
	'lightsnowandthunder'			=> 'Light snow and thunder',
	'lightsnowshowers'				=> 'Light snow showers',
	'lightssleetshowersandthunder'	=> 'Light sleet showers and thunder',
	'lightssnowshowersandthunder'	=> 'Light snow showers and thunder',
	'partlycloudy'					=> 'Partly cloudy',
	'rain'							=> 'Rain',
	'rainandthunder'				=> 'Rain and thunder',
	'rainshowers'					=> 'Rain showers',
	'rainshowersandthunder'			=> 'Rain showers and thunder',
	'sleet'							=> 'Sleet',
	'sleetandthunder'				=> 'Sleet and thunder',
	'sleetshowers'					=> 'Sleet showers',
	'sleetshowersandthunder'		=> 'Sleet showers and thunder',
	'snow'							=> 'Snow',
	'snowandthunder'				=> 'Snow and thunder',
	'snowshowers'					=> 'Snow showers',
	'snowshowersandthunder'			=> 'Snow showers and thunder'
);

# Parse JSON
open(JSON, 'forecast.json');
my $json = decode_json(join("", <JSON>));
close JSON;

#Define variables used in display
my (@symbols, @temperatures, @types, @winds, @press, @windir, @precip, @found, @aurora);
my @maxtemps = (-100)x31;
my @mintemps = (100)x31;

# What time is it now?
my $dt = DateTime->now(time_zone => 'Europe/Oslo');
my $time = $dt->strftime('%Y-%m-%d %T');
my $today = $dt->day();

# Sunrise and sunset times
my $sunrise = DateTime::Event::Sunrise->new(longitude => +5.338, latitude  => +60.3);
$rise = sprintf("%02d",$sunrise->sunrise_datetime($dt)->hour) . ":" .  sprintf("%02d",$sunrise->sunrise_datetime($dt)->minute);
$set  = sprintf("%02d",$sunrise->sunset_datetime($dt)->hour) . ":" . sprintf("%02d",$sunrise->sunset_datetime($dt)->minute);

# Iterate through information received from API (1-hour for close dates, 6 and 12 hour for extended forecast)
for(@{$json->{'properties'}->{'timeseries'}}) {
	my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = strptime($_->{'time'});
	
	# Symbol code (Also used as weather description)
	my $symbol = $_->{'data'}->{'next_6_hours'}->{'summary'}->{'symbol_code'};
	
	# Current time period's instant forecast
	my $instant = $_->{'data'}->{'instant'}->{'details'};
	
	# Use midday unless current day is already past noon (Guaranteed to have a 12:00 forecast)
	if(($hour == 12 || $today == $mday) && $found[$mday] == 0) {

		# Find weather symbol and matching text
		my @symboldesc 	= split("_", $symbol);
		$types[$mday]  = $weatherdesc{$symboldesc[0]};
		$symbols[$mday] = $symbol;

		# Find data for current day
		$temperatures[$mday] = int($instant->{'air_temperature'}) . "\xB0";
		$winds[$mday]		= sprintf("%0.1f", $instant->{'wind_speed'});
		$press[$mday]		= sprintf("%03d", $instant->{'air_pressure_at_sea_level'});
		$windir[$mday]		= $instant->{'wind_from_direction'};

		# Find beaufort equivalent of wind
		my $windscale = "";
		foreach my $key (sort {$a <=> $b} keys %beaufort) {
			if($winds[$mday] > $key) { $windscale = $beaufort{$key}; }
		}
		$winds[$mday] = $windscale;

		# Find direction of wind
		my $direction = "";
		foreach my $key (sort {$a <=> $b} keys %directions) {
			if($windir[$mday] > $key) {	$direction = $directions{$key};	}
		}
		$windir[$mday] = $direction;

		# Used for current day, if already found for this day, don't process these further so that we don't end up with just midnight.
		$found[$mday] = 1;
	}

	# Minimum air temperature for the day
	my $airmin = $_->{'data'}->{'next_6_hours'}->{'details'}->{'air_temperature_min'};
	if($airmin) {
		$airmin = sprintf("%0.1f", $airmin);
		if($airmin <= $mintemps[$mday]) {
			$mintemps[$mday] = $airmin;
		}
	}

	# Maximum air temperature for the day
	my $airmax = $_->{'data'}->{'next_6_hours'}->{'details'}->{'air_temperature_max'};
	if($airmax) {
		$airmax = sprintf("%0.1f", $airmax);
		if($airmax >= $maxtemps[$mday]) {
			$maxtemps[$mday] = $airmax;
		}
	}

	# Add up one hour precip, this may not be really accurate for extended forecast.
	my $preciplong = $_->{'data'}->{'next_6_hours'}->{'details'}->{'precipitation_amount'};
	my $precipshort = $_->{'data'}->{'next_1_hours'}->{'details'}->{'precipitation_amount'};
	if($precipshort ne "") {
		$precip[$mday] += $precipshort;
	}
	elsif($preciplong ne "") {
		$precip[$mday] += $preciplong;
	}

}

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
open(IN,"fontdata-yr.info");
for(<IN>) {
	chomp $_;
	my @data = split(" ",$_);
	$fontdata{$data[0]} = $data[1];
}
close IN;

# Parse aurora forecast JSON
open(IN,"aurora.info");
my $aurora = decode_json(join("", <IN>));
close IN;

for(@{$aurora}) {
	my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = strptime($_->{'predicted_time'});
	if ($_->{'kp'} < 5) {
		$aurora[$mday] = $_->{'kp'};
	}
	else {
		$aurora[$mday] = "*" . $_->{'kp'} . "*"; 
	}
}

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
	$x = $image->Annotate ( font=>'weathericons-regular-webfont.ttf', pointsize=>76, antialias=>'false',
		fill=>'black', text=>$fontdata{$symbols[$ldt]}, align=>'Center', x=> 64 + 128*$t, y=>84);

	#Write temperature
	$x = $image->Annotate(font=>'OpenSans-Bold.ttf', pointsize=>46, antialias=>'false',
		fill=>'black', text=>$temperatures[$ldt], align=>'Center', x=> 54 + 128*$t, y=>$texty);
	$x = $image->Annotate(font=>'tamsyn-webfont.ttf', pointsize=>14, antialias=>'false',
		fill=>'black', text=>$mintemps[$ldt] . "\xB0", align=>'Center', x=> 102 + 128*$t, y=>$texty);	
	$x = $image->Annotate(font=>'tamsyn-webfont.ttf', pointsize=>14, antialias=>'false',
		fill=>'black', text=>$maxtemps[$ldt] . "\xB0", align=>'Center', x=> 102 + 128*$t, y=>$texty - 24);	

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
		fill=>'black', text=>sprintf("%0.1f", $precip[$ldt]) . " mm", 
		align=>'Center', x=> 64 + 128*$t, y=>$texty+140);

	#Write pressures
	$x = $image->Annotate(font=>'tamsyn-webfont.ttf', pointsize=>14, antialias=>'false',
		fill=>'black', text=>$press[$ldt] . " hPa", 
		align=>'Center', x=> 64 + 128*$t, y=>$texty+155);

	#Write aurora predictions
	$x = $image->Annotate(font=>'tamsyn-webfont.ttf', pointsize=>14, antialias=>'false',
		fill=>'black', text=>$aurora[$ldt] . " kp", 
		align=>'Center', x=> 64 + 128*$t, y=>$texty+170);

}

# Draw border
$x = $image->Draw(primitive=>'Rectangle', fill=>'none', stroke=>'black', strokewidth=>2, points=>'0, 0, 639, 383');

# Text for finance and sunrise info
$btc = sprintf("%2d", $btc);
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
print "Content-Type: image/$ftype\nContent-Disposition: inline; filename=\"epaper.$ftype\"\n\n"; # For arduino
binmode STDOUT;
$x = $image->Write($str);
