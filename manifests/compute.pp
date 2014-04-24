class role_openstack::compute(
  
  $ceph_cinder_key,
  $cinder_rbd_secret_uuid,
  $nova_user_password,
  $rabbit_password,
  $nova_db_password,
  $control_ip_address,
  $neutron_user_password,

  $openstack_cluster_id,

  $image_cache_size_gb  = 250,

  $raid_disks           = [],
  $raid_dev_name        = '/dev/md2',
  $libvirt_type         = 'kvm',
  $volume_backend       = 'lvm',
  $ceph_fsid            = 'false',
  $region               = 'Leiden',
  
  

){
  
  include stdlib

  $ipaddresses = ipaddresses()
  $host_aliases = flatten([ $::fqdn, $::hostname, $ipaddresses ])

  @@sshkey { "${::fqdn}_dsa_${::sshrsakey}":
    host_aliases => $host_aliases,
    type => dsa,
    key => $::sshdsakey,
    tag => $openstack_cluster_id,
  }
  
  @@sshkey { "${::fqdn}_rsa_${::sshrsakey}":
    host_aliases => $host_aliases,
    type => rsa,
    key => $::sshrsakey,
    tag => $openstack_cluster_id,
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

  file { "nova-ssh-dir":
    path    => "/var/lib/nova/.ssh",
    ensure  => "directory",
    require => File['/var/lib/nova'],
    mode    => 0770,
    owner   => 'nova',
  }

  #file { "nova-strickhostcheckingdisable":
  #  path    => '/var/lib/nova/.ssh/config',
  #  content => template('role_openstack/ssh_config.erb'),
  #  require => File["nova-ssh-dir"],
  #}
  file {"link to known hosts":
    ensure => link,
    path   => '/var/lib/nova/.ssh/known_hosts',
    target => '/etc/ssh/ssh_known_hosts',
    require => File['nova-ssh-dir'],
  }

  exec { "nova-copy-host-pup-key":
    command => "/bin/cp /etc/ssh/ssh_host_rsa_key /var/lib/nova/.ssh/id_rsa && /bin/chown nova:nova /var/lib/nova/.ssh/id_rsa",
    require => File["nova-ssh-dir"],
    unless  => '/usr/bin/diff /etc/ssh/ssh_host_rsa_key /var/lib/nova/.ssh/id_rsa',
  }

  if $ceph_fsid != 'false' {
    file {'/etc/ceph':
      ensure => directory,
    }
    
    #class {'sshkey_distribute':
    #  export_tag => $openstack_cluster_id,
    #}

    #Exec <<| tag == $openstack_cluster_id |>> 

  

    Ini_setting <<| tag == "cephconf-${$ceph_fsid}" |>> {
      require => File['/etc/ceph'],
    }
    
    class { 'role_openstack::ceph::package': }
    
    file {'/tmp/secret.xml':
      ensure => present,
      content => template('role_openstack/secret.xml.erb')
    } ~>

    exec {'define secret':
      command     => '/usr/bin/virsh secret-define --file /tmp/secret.xml',
      require     =>  Class[nova::compute::libvirt],
      refreshonly => true,
    } ~>

    exec {'set secret value':
      command     => "/usr/bin/virsh secret-set-value --secret ${cinder_rbd_secret_uuid} --base64 ${ceph_cinder_key}",
     # require    => [File['/etc/ceph/ceph.client.cinder.keyring'],Exec['define secret']],
      notify      => Service['nova-compute'],
      refreshonly => true,
    }



  }

  if size($raid_disks) < 4 {
    fail("raid disks (${raid_disks}) must have at least 4 (current = ${raid_disk_number}) disks, otherwise raid 10 can\'t be made")
  }

  $raid_string = join($raid_disks, " ")
  $raid_disk_number = size($raid_disks)
  $raid_dev_name_split = split($raid_dev_name,'/')
  $raid_dev_only_name = $raid_dev_name_split[-1]
  notice($raid_dev_only_name)
  exec {'create raid':
    command => "/sbin/mdadm --create --auto=yes ${raid_dev_name} --level=10 --raid-devices=${raid_disk_number} ${raid_string}",
    unless  => "/bin/lsblk | /bin/grep ${raid_dev_only_name}",
  }

  physical_volume { $raid_dev_name:
    ensure => present,
    require => Exec['create raid']
  }

  volume_group {'instance-volumes':
    ensure => present,
    physical_volumes => $raid_dev_name,
  #  before => Class['openstack::repo'],
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
  
  #class {'openstack::repo': 
  #  before => Exec['apt-get-update after repo addition'],
  #} ~>
  apt::source { 'ubuntu-cloud-archive':
    location          => 'http://ubuntu-cloud.archive.canonical.com/ubuntu',
    release           => "precise-updates/havana",
    repos             => 'main',
    required_packages => 'ubuntu-cloud-keyring',
  } ~>
  
  exec {'apt-get-update after repo addition':
    command     => '/usr/bin/apt-get update',
    unless      => '/usr/bin/test -f /etc/apt/sources.list.d/ubuntu-cloud-archive.list',
    refreshonly => true,
    before      => [
      Class[nova],
      Class[nova::compute],
      Class[nova::compute::libvirt],
      Class[nova::compute::neutron],
      Class[neutron],
      Class[neutron::agents::ovs],
      Class[nova::network::neutron]
    ],
  }
  
  class { 'nova':
    sql_connection      => "mysql://nova:${nova_db_password}@${control_ip_address}/nova",
    rabbit_userid       => 'openstack',
    rabbit_password     => $rabbit_password,
    image_service       => 'nova.image.glance.GlanceImageService',
    glance_api_servers  => "${control_ip_address}:9292",
    rabbit_host         => $control_ip_address,
    rabbit_virtual_host => '/',
    debug               => true,
  }

  class { 'nova::compute':
    enabled                       => true,
    vnc_enabled                   => true,
    vncserver_proxyclient_address => $::ipaddress_eth0,
    vncproxy_host                 => $control_ip_address,
  }

  class { 'nova::compute::libvirt':
    libvirt_type      => $libvirt_type,
    vncserver_listen  => '0.0.0.0',
#    vncserver_listen  => $::ipaddress_eth0,1
    migration_support => true,
  }
  
#  class {'nova::compute::spice':
#    agent_enabled               => false,
#    server_listen               => $ipaddress_eth0,
#    server_proxyclient_address  => $::ipaddress_eth0,
#    proxy_host                  => $control_ip_address,
# }

  class { 'nova::compute::neutron': 
    libvirt_vif_driver => 'nova.virt.libvirt.vif.LibvirtGenericVIFDriver',
  } 

  class { 'neutron':
    enabled               => true,
    bind_host             => '0.0.0.0',
    allow_overlapping_ips => false,
    rabbit_host           => $control_ip_address,
    rabbit_virtual_host   => '/',
    rabbit_user           => 'openstack',
    rabbit_password       => $rabbit_password,
    debug                 => false,
  }

  class { 'neutron::agents::ovs':
      bridge_uplinks   => [],
      bridge_mappings  => [],
      enable_tunneling => true,
      local_ip         => $::ipaddress_eth0,
      firewall_driver  => false,
  }

  class { 'nova::network::neutron':
      neutron_admin_password    => $neutron_user_password,
      neutron_auth_strategy     => 'keystone',
      neutron_url               => "http://${control_ip_address}:9696",
      neutron_admin_username    => 'neutron',
      neutron_admin_tenant_name => 'services',
      neutron_admin_auth_url    => "http://${control_ip_address}:35357/v2.0",
      security_group_api        => 'neutron',
      neutron_region_name       => $region,
  }


  ini_setting { 'set_force_raw_images':
    path              => '/etc/nova/nova.conf',
    section           => 'DEFAULT',
    key_val_separator => '=',    
    setting           => 'force_raw_images',
    value             => 'True',
    ensure            => present,
    require           => File['/etc/nova/nova.conf'],
    notify            => Service['nova-compute'],
  }

  ini_setting { 'set_cow_images':
    path              => '/etc/nova/nova.conf',
    key_val_separator => '=',    
    section           => 'DEFAULT',
    setting           => 'use_cow_images',
    value             => 'True',
    ensure            => present,
    require           => File['/etc/nova/nova.conf'],
    notify            => Service['nova-compute'],
  }

  ini_setting { 'set_live_migration_flag':
    path              => '/etc/nova/nova.conf',
    key_val_separator => '=',    
    section           => 'DEFAULT',
    setting           => 'live_migration_flag',
    value             => 'VIR_MIGRATE_UNDEFINE_SOURCE,VIR_MIGRATE_PEER2PEER,VIR_MIGRATE_LIVE',
    ensure            => present,
    require           => File['/etc/nova/nova.conf'],
    notify            => Service['nova-compute'],
  }

#  class {'openstack::compute':
#    # Required Network
#    internal_address => $::ipaddress_eth0,
#  # Required Nova
#    nova_user_password => $nova_user_password,
#  # Required Rabbit
#    rabbit_password => $rabbit_password,
#  # DB
#    nova_db_password => $nova_db_password,
#    db_host => $control_ip_address,
#  # Nova Database
#    nova_db_user => 'nova',
#    nova_db_name => 'nova',
#  # Network
#    public_interface => 'eth0',
#    private_interface => 'eth1',
#    fixed_range => undef,
#    network_manager => 'nova.network.manager.FlatDHCPManager',
#    network_config => {},
#    multi_host => true,
#    enabled_apis => 'ec2,osapi_compute,metadata',
#  # Neutron
#    neutron => true,
#    neutron_user_password => $neutron_user_password,
#    neutron_admin_tenant_name => 'services',
#    neutron_admin_user => 'neutron',
#    enable_ovs_agent => true,
#    enable_l3_agent => false,
#    enable_dhcp_agent => false,
#    neutron_auth_url => "http://${control_ip_address}:35357/v2.0",
#    keystone_host => $control_ip_address,
#    neutron_host => $control_ip_address,
#    ovs_enable_tunneling => true,
#    ovs_local_ip => $::ipaddress_eth0,
#    neutron_firewall_driver => false,
#    bridge_mappings => undef,
#    bridge_uplinks => undef,
#    security_group_api => 'neutron',
#  # Nova
#    nova_admin_tenant_name => 'services',
#    nova_admin_user => 'nova',
#    purge_nova_config => false,
#    libvirt_vif_driver => 'nova.virt.libvirt.vif.LibvirtGenericVIFDriver',
#  # Rabbit
#    rabbit_host => $control_ip_address,
#    rabbit_hosts => false,
#    rabbit_user => 'openstack',
#    rabbit_virtual_host => '/',
#  # Glance
#    glance_api_servers => "${control_ip_address}:9292",
#  # Virtualization
#    libvirt_type => $libvirt_type,
#  # VNC
#    vnc_enabled => true,
#    vncproxy_host => $control_ip_address,
#    vncserver_listen => false,
#  # cinder / volumes
#  # manage_volumes => true, 
#  #  manage_volumes => false,
#  #  cinder_volume_driver => 'iscsi',
#  #  cinder_db_password => 'Openstack_123',
#  #  cinder_db_user => 'cinder',
#  #  cinder_db_name => 'cinder',
#  #  volume_group => 'cinder-volumes',
#  #  iscsi_ip_address => '10.61.2.69',
#  #  setup_test_volume => false,
#  #  cinder_rbd_user => 'volumes',
#  #  cinder_rbd_pool => 'volumes',
#  #  cinder_rbd_secret_uuid => false,
#  # General
#    migration_support => false,
#    verbose => false,
#    force_config_drive => false,
#   # use_syslog => false,
#   # log_facility => 'LOG_USER',
#    enabled => true,
#  }


}