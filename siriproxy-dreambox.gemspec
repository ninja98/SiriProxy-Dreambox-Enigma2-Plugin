# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)

Gem::Specification.new do |s|
  s.name        = "siriproxy-dreambox"
  s.version     = "0.4.2"
  s.authors     = ["ninja98"]
  s.email       = [""]
  s.homepage    = ""
  s.summary     = %q{Siri and Dreambox Enigma2 plugin}
  s.description = %q{Control your dreambox with Siri. You need an engima2 dreambox. Contact me on twitter @ninja98 is you have questions}

  s.rubyforge_project = "siriproxy-dreambox"

  s.files         = `git ls-files 2> /dev/null`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/* 2> /dev/null`.split("\n")
  s.executables   = `git ls-files -- bin/* 2> /dev/null`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  # s.add_development_dependency "rspec"
  s.add_runtime_dependency "hpricot"
  s.add_runtime_dependency "twitter"
end

