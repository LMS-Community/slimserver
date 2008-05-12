1. LICENSE
==========
Copyright (C) 2008 Erland Isaksson (erland_i@hotmail.com)

This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Lesser General Public
License as published by the Free Software Foundation; either
version 2.1 of the License, or (at your option) any later version.

This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public
License along with this library; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA


2. PREREQUISITES
================
- A SqueezeCenter 7.0 or later installed and configured
- A SqueezeBox with display or a SqueezeBox Boom if you like to use the DAC image loading features


3. INSTALLATION AND USAGE
=========================
Appears under "Extras/ABTester", there are two type of tests:

ABX tests:
- Load data A: Loads the data associated with A
- Load data B: Loads the data associated with B
- Load data X: Loads either the data associated with A or B. 
- The selection of X is made when you enter the specific testcase, so you can switch between A, B and X as many times as you like. 
- You can switch between A, B and X either by selecting one of the "Load data" menus or by hitting the numbers 1, 2 or 3.
- A new selection of X will be made when you exit and enter the test case again.
- Use the "Check X" menu if you like to see what X represents

ABCD tests:
- Load data A: Loads the data associated with A
- Load data B: Loads the data associated with B
- Load data C: Loads the data associated with C
- Load data D: Loads the data associated with D
- You can switch between A, B, C and D either by selecting one of the "Load data" menus or by hitting the numbers 1, 2, 3, 4 or 5.

Besides tests, you can also load standard DAC images on a SqueezeBox Boom. 
This is done either by selecting an image in the "Extras/ABTester/Standard images" menu or by assiging a remote button using a custom.map file.
If assigning an image to a remote button, the image needs to be stored in the Plugins/ABTester/StandardImages directory and you will need a custom.map file
that looks something like this:


[common]
# Load the image in Plugins/ABTester/StandardImages/boom5.i2c when the user push the 7 button
7       = modefunction_Plugins::ABTester::Plugin->loadStandardImage_boom5.i2c


4. AUTOMATIC LOADING OF IMAGE
=============================
By default the plugin will try to load the following image when a client reconnects to SqueezeCenter
Plugins/ABTester/StandardImages/default.i2c


5. CREATION OF TEST CASES
=========================
There are some sample testcases in Plugins/ABTester/Examples, the real testcases which can be used from the user interface
is stored in Plugins/ABTester/Images.

A testcase can either be package as a zip file which contains all the test case files or as sub directory which contains all
the necessary files. The zip file or the sub directory needs to be placed in the Plugins/ABTester/Images directory.

Each testcase has a test.xml file which describes the files and commands that are part of the testcase.
You can see a number of test.xml file sample in the bundled plugin in the sub directories below Plugins/ABTester/Images and also
in the directory Plugins/ABTester/Examples.

The test.xml file can contain the following different elements:

- To specify that the image file image1.i2c should be loaded when the user select "Load data A":
  <image id="A">image1.i2c</image>

- To specify that the audio file track1.mp3 should be played when the user select "Load data A":
  <audio id="A">image1.i2c</audio>

- To specify that the perl function "main" in the "set_stereoxl" perl package should be called with the arguments "Boom" and "-6" when the user select "Load data A":
- The set_stereoxl either needs to be loaded already or stored in a set_stereoxl.pm file in the test case directory
- $PLAYERNAME will be replaced with the name of the current player
  <perlfunction id="B">set_stereoxl::main $PLAYERNAME -6</perlfunction>

- To specify that the system command "cd /usr/share/squeezecenter/Plugins/ABTester/Images/mytestcase;set_stereoxl.pl Boom -6" should be executed when the user select "Load data A"
- $TESTDIR will be replaced with the test case directory
- $PLAYERNAME will be replaced with the name of the current player
  <script id="B">cd $TESTDIR;perl set_stereoxl.pl $PLAYERNAME -6</script>

- To specify that the CLI command "mixer volume 5" should be exeuted when the user enters the test case:
  <init id="1" type="cli">mixer volume 5</init>

- To specify that the user should have to respond to two questions in a ABCD test case:
  <question id="1">Bass quality ?</question>
  <question id="2">Overall sound quality ?</question>


Besides the above mentioned elements, there is also a number of optional elements that can be used to restrict in which environment a test case can be executed:

- To specify that a test case only can be used on a Squeezebox Boom player (you can specify a comma separated list of supported models)
  <requiredmodels>boom</requiredmodels>

- To specify that the test case only can be used if the BoomDac plugin is installed and enabled (you can specify a comma separated list of plugins required)
  <requiredplugins>BoomDac</requiredplugins>

- To specify that the test case needs minimum firmware version 7
  <minfirmware>7</minfirmware>

- To specify that the test case only should be available on Linux and Mac platforms:
  <requiredos>unix,mac</requiredos>


Finally, you may enter a "instruction" for the test case that describes the test case and what you like the user to look for:
  <instructions>Listen to the bass (Keep the volume low when changing test data)</instructions>

