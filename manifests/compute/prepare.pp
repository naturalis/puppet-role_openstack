# == Class: role_openstack::compute::prepare()
#
class role_openstack::compute::prepare(
  $openstack_cluster_id,
  $instance_volume_device,
  $image_cache_size_gb,
){

  include stdlib

  $ipaddresses = ipaddresses()
  $host_aliases = flatten([ $::fqdn, $::hostname, $ipaddresses ])

  @@sshkey { "${::fqdn}_dsa_${::sshrsakey}":
    host_aliases  => $host_aliases,
    type          => dsa,
    key           => $::sshdsakey,
    tag           => $openstack_cluster_id,
  }

  @@sshkey { "${::fqdn}_rsa_${::sshrsakey}":
    host_aliases => $host_aliases,
    type         => rsa,
    key          => $::sshrsakey,
    tag          => $openstack_cluster_id,
  }

  @@ssh_authorized_key { "${::fqdn}_rsa_${::sshrsakey}":
    ensure   => present,
    key      => $::sshrsakey,
    type     => ssh-rsa,
    user     => 'nova',
    tag      => $openstack_cluster_id,
  }

  Sshkey <<| tag == $openstack_cluster_id |>> {
    ensure => present,
  }

  Ssh_authorized_key <<| tag == $openstack_cluster_id |>> {
    ensure => present,
  }

  #user {'nova':
  #  ensure => present,
  #  shell  => '/bin/bash',
  #  home   => '/var/lib/nova'
  #}

  exec { 'set nova shell':
    command => '/usr/sbin/usermod -s /bin/bash nova',
    unless  => '/bin/cat /etc/passwd | grep nova | grep bash',
    require => User['nova'],
  }

  file { 'nova-ssh-dir':
    ensure  => 'directory',
    path    => '/var/lib/nova/.ssh',
    require => File['/var/lib/nova'],
    mode    => '0770',
    owner   => 'nova',
  }

  #file { "nova-strickhostcheckingdisable":
  #  path    => '/var/lib/nova/.ssh/config',
  #  content => template('role_openstack/ssh_config.erb'),
  #  require => File["nova-ssh-dir"],
  #}
  file {'link to known hosts':
    ensure  => link,
    path    => '/var/lib/nova/.ssh/known_hosts',
    target  => '/etc/ssh/ssh_known_hosts',
    require => File['nova-ssh-dir'],
  }



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
