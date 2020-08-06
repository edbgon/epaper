# epapergen
E-Paper picture generator. 

Grabs weather data from openweathermap and creates a display with ImageMagick in Perl.

Currently uses IoT electric imp service to grab data from website and transmit as PBM to device which then uploads the image over SPI.

There is a plan on replacing with ESP8266 style control to not rely on external services for application function.
The ePaper display uses SPI along with some extra command/chip-select type functions.
