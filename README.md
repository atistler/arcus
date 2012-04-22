# Arcus

A library that provides a clean API into Cloudstack REST calls. Also included is a CLI tool for making Cloudstack REST calls

## Installation

Add this line to your application's Gemfile:

    gem 'arcus'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install arcus

## Usage

Cloudstack REST commands are read in from the commands.xml file.  This provides a list of required and optional arguments
for each Cloudstack command.  Each Cloudstack command is split up into an action and a target, for instance listVirtualMachines
becomes: [action -> list, target -> VirtualMachine].  The arcus will create a dynamic class based on the name of the target and
a method named after the action.  So you can do the following:

vms = VirtualMachine.new.list.fetch

vms will be a object containing the results of "listvirtualmachinesresponse"

Other "response_types" are allowed, for example:

vms = VirtualMachine.new.list.fetch(:yaml)
vms = VirtualMachine.new.list.fetch(:xml)
vms = VirtualMachine.new.list.fetch(:prettyxml)
vms = VirtualMachine.new.list.fetch(:json)
vms = VirtualMachine.new.list.fetch(:prettyjson)

Each of these calls will return a string representation in the format specified.

You can also give arguments to the "action" method.  For example:

vms = VirtualMachine.new.list({id: 1}).fetch(:json)

will produce the http call -> /client/api?id=1&response=xml&command=listVirtualMachines


## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
