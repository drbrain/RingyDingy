require 'hoe'

Hoe.plugin :git
Hoe.plugin :minitest
Hoe.plugin :travis

Hoe.spec 'RingyDingy' do |p|
  p.developer 'Eric Hodel', 'drbrain@segment7.net'

  self.readme_file  = 'README.rdoc'
  self.history_file = 'History.rdoc'
  self.licenses << 'BSD-3-Clause'
  self.testlib = :minitest

  rdoc_locations <<
    'docs.seattlerb.org:/data/www/docs.seattlerb.org/RingyDingy/'

  p.extra_dev_deps << ['ZenTest', '~> 4.8']
end

# vim: syntax=Ruby
