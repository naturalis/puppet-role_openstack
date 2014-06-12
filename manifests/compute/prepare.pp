# == Class: role_openstack::compute::prepare()
#
class role_openstack::compute::prepare(
  $openstack_cluster_id,
  $instance_volume_device,
  $image_cache_size_gb,
){

  



  physical_volume { $instance_volume_device:
    ensure => present,
  }

  volume_group {'instance-volumes':
    ensure           => present,
    physical_volumes => $instance_volume_device,
  }

  logical_volume {'nova_lib_volume':
    ensure        => present,
    volume_group  => 'instance-volumes',
    size          => "${image_cache_size_gb}G",
  }

  filesystem  {'/dev/instance-volumes/nova_lib_volume':
    ensure  => present,
    fs_type => 'ext4',
    require => Logical_volume['nova_lib_volume'],
  }

  file {'/var/lib/nova':
    ensure => directory,
  }

  mount {'/var/lib/nova':
    ensure    => mounted,
    atboot    => true,
    device    => '/dev/instance-volumes/nova_lib_volume',
    fstype    => 'ext4',
    options   => 'defaults',
    remounts  => true,
    require   => [
      Filesystem['/dev/instance-volumes/nova_lib_volume'],
      File['/var/lib/nova']
    ],
    before    => [
      Exec['apt-get-update after repo addition'],
      Package['nova-common'],
      ],
  }

  package { 'ethtool':
    ensure => present,
  }

  # this is to fix network speed
  exec { 'set gro to off':
    command => '/sbin/ethtool --offload eth0 gro off',
    unless  => '/sbin/ethtool --show-offload eth0 | /bin/grep generic-receive-offload | /bin/grep off',
    require => Package['ethtool'],
  }


  package {'ubuntu-cloud-keyring':
    ensure => present,
    before => File['/etc/apt/sources.list.d/ubuntu-cloud-archive.list'],
  }

  file {'/etc/apt/sources.list.d/ubuntu-cloud-archive.list':
    ensure    => present,
    mode      => '0644',
    content   => template('role_openstack/ubuntu-cloud-archive.list.erb'),
  }

  exec {'apt-get-update after repo addition':
    command       => '/usr/bin/apt-get update',
    refreshonly   => true,
    subscribe     => File['/etc/apt/sources.list.d/ubuntu-cloud-archive.list'],
  }

}
