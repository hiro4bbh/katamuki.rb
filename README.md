# katamuki.rb - a simple Gradient Boosting library written in Ruby
![katamuki.rb logo](https://rawgit.com/hiro4bbh/katamuki.rb/master/icon_title.svg)

[![Build Status](https://travis-ci.org/hiro4bbh/katamuki.rb.svg?branch=master)](https://travis-ci.org/hiro4bbh/katamuki.rb)

Copyright 2017- Tatsuhiro Aoshima (hiro4bbh@gmail.com).

## What is katamuki.rb?
katamuki.rb is a simple Gradient Boosting library written in Ruby.

Currently, katamuki.rb cannot be used in general settings, because
katamuki.rb only supports data in `JgramDatabase*`, which is required for
running `sample/syscalls`.

## How to use katamuki.rb?
Currently, katamuki.rb is extremely unstable, so there is no gem for
katamuki.rb or installation scripts for deployment.

You can use katamuki.rb on macOS from GitHub, as the following:

```bash
# Get latest katamuki.rb from GitHub.
git clone https://github.com/hiro4bbh/katamuki.rb
cd katamuki.rb
git submodule update --init
# You can use OpenBLAS optimized for your machine.
brew install homebrew/science/openblas --build-from-source
# Use latest Ruby (currently tested on version 2.4.0p0).
brew install ruby
# Install FFI for OpenBLAS interface.
gem install ffi
# Happy hacking with katamuki.rb :)
./bin/katamuki.rb
```

You can see yardoc at http://www.rubydoc.info/github/hiro4bbh/katamuki.rb .
__WARNING: yardoc has many bugs for katamuki.rb documentation, be careful!!__
