#
#
#
#
class role_openstack::control::prepare(
  $lvm_volume_disks,
)
{

  file {'/etc/network/interfaces':
    ensure    => present,
    mode      => '0644',
    content   => template('role_openstack/interfaces.erb'),
  }

  exec {'set interface eth1 to up':
    command   => '/sbin/ifconfig eth1 up',
    unless    => '/sbin/ifconfig | /bin/grep eth1',
    require   => File['/etc/network/interfaces'],
  }

  # do use local storage for glance/cinder
  package {'lvm2':
    ensure => present,
  }

  exec {"/sbin/pvcreate ${lvm_volume_disks}":
    unless   => "/sbin/pvdisplay ${lvm_volume_disks}",
    require  => Package['lvm2'],
  }

  exec {"/sbin/vgcreate cinder-volumes ${lvm_volume_disks}":
    unless   => '/sbin/vgdisplay cinder-volumes',
    require  => Exec["/sbin/pvcreate ${lvm_volume_disks}"],
    before   => Apt::Source['ubuntu-cloud-archive'],
  }


  package { 'ethtool':
    ensure => present,
  }

  # this is to fix network speed
  exec { 'set gro to off':
    command => '/sbin/ethtool --offload eth1 gro off',
    unless  => '/sbin/ethtool --show-offload eth1 | /bin/grep generic-receive-offload | /bin/grep off',
    require => Package['ethtool'],
  }

  package {'ubuntu-cloud-keyring':
    ensure => present,
    before =>  Apt::Source['ubuntu-cloud-archive'],
  }

  apt::source { 'ubuntu-cloud-archive':
    location          => 'http://ubuntu-cloud.archive.canonical.com/ubuntu',
    release           => 'precise-updates/havana',
    repos             => 'main',
  #  required_packages => 'ubuntu-cloud-keyring',
  } ~>

  exec {'apt-get-update after repo addition':
    command       => '/usr/bin/apt-get update',
    refreshonly   => true,
  }

}
