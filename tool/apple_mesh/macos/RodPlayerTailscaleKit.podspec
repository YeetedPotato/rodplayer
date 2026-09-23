Pod::Spec.new do |spec|
  spec.name = 'RodPlayerTailscaleKit'
  spec.version = '0.1.0'
  spec.summary = 'Pinned TailscaleKit build artifact for RodPlayer.'
  spec.homepage = 'https://github.com/tailscale/libtailscale'
  spec.license = { :type => 'BSD-3-Clause' }
  spec.author = 'RodPlayer'
  spec.source = { :git => 'https://github.com/tailscale/libtailscale', :commit => '59d4bb82744915815178e0f0776d60026a397ee7' }
  # Oldest supported OS; CI chooses the newest SDK independently.
  spec.osx.deployment_target = '15.0'
  spec.vendored_frameworks = 'TailscaleKit.framework'
end
