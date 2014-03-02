class role_openstack::compute(
  
  $ceph_cinder_key,
  $cinder_rbd_secret_uuid,
  $nova_user_password,
  $rabbit_password,
  $nova_db_password,
  $control_ip_address,
  $neutron_user_password,

  $raid_disks = [],
  $raid_dev_name = '/dev/md2',
  $libvirt_type = 'kvm',
  $volume_backend = 'lvm',
  $ceph_fsid = 'false',
  
  

){
  include stdlib
  if $ceph_fsid != 'false' {
    file {'/etc/ceph':
      ensure => directory,
    }

    Ini_setting <<| tag == "cephconf-${$ceph_fsid}" |>> {
      require => File['/etc/ceph'],
    }

    class { 'role_openstack::ceph::package': }
    
    file {'/tmp/secret.xml':
      ensure => present,
      content => template('role_openstack/secret.xml.erb')
    } ~>

    exec {'define secret':
      command => '/usr/bin/virsh secret-define --file /tmp/secret.xml',
    #  require => File['/tmp/secret.xml'],
    } ~>

    exec {'set secret value':
      command => "/usr/bin/virsh secret-set-value --secret ${cinder_rbd_secret_uuid} --base64 ${ceph_cinder_key}",
     # require => [File['/etc/ceph/ceph.client.cinder.keyring'],Exec['define secret']],
      notify => Service['nova-compute'],
    }



  }

  if size($raid_disks) < 4 {
    fail("raid disks (${raid_disks}) must have at least 4 (current = ${raid_disk_number}) disks, otherwise raid 10 can\'t be made")
  }

  $raid_string = join($raid_disks, " ")
  $raid_disk_number = size($raid_disks)

  exec {'create raid':
    command => "/sbin/mdadm --create --auto=yes ${raid_dev_name} --level=10 --raid-devices=${raid_disk_number} ${raid_string}",
    unless  => "/bin/grep ${raid_dev_name}",
  }

  physical_volume { $raid_dev_name:
    ensure => present,
    require => Exec['create raid']
  }

  volume_group {'instance-volumes':
    ensure => present,
    physical_volumes => $raid_dev_name,
    before => Class['openstack::repo'],
  }

  
  class {'openstack::repo': 
#    before => Exec['apt-get-update after repo addition']
  } ->

  exec {'apt-get-update after repo addition':
    command => '/usr/bin/apt-get update',
    unless => '/usr/bin/test -f /etc/apt/sources.list.d/ubuntu-cloud-archive.list',
    before => [
      Class[nova],
      Class[nova::compute],
      Class[nova::compute::libvirt],
      Class[nova::compute::neutron],
      Class[neutron],
      Class[neutron::agents::ovs],
      Class[nova::neutron::network]
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
    debug               => false,
  }

  class { 'nova::compute':
    enabled                       => true,
    vnc_enabled                   => true,
    vncserver_proxyclient_address => $::ipaddress_eth0,
    vncproxy_host                 => $control_ip_address,
  }

  class { 'nova::compute::libvirt':
    libvirt_type      => $libvirt_type,
    vncserver_listen  => $::ipaddress_eth0,
  } 

  class { 'nova::compute::neutron': } 

  class { 'neutron':
    enabled               => true,
    bind_host             => '0.0.0.0',
    allow_overlapping_ips => true,
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
  }

  class { 'nova::network::neutron':
      neutron_admin_password    => $neutron_user_password,
      neutron_auth_strategy     => 'keystone',
      neutron_url               => "http://${control_ip_address}:9696",
      neutron_admin_username    => 'neutron',
      neutron_admin_tenant_name => 'services',
      neutron_admin_auth_url    => "http://${control_ip_address}:35357/v2.0",
      security_group_api        => 'neutron'
  }

#  class {'openstack::compute':
#  	 # Required Network
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


  
  
  ini_setting { 'set_libvirt_images_type':
    path              => '/etc/nova/nova.conf',
    section           => 'DEFAULT',
    key_val_separator => '=',    
    setting           => 'libvirt_images_type',
    value             => 'lvm',
    ensure            => present,
    require           => File['/etc/nova/nova.conf'],
    notify            => Service['nova-compute'],
  }

  ini_setting { 'set_libvirt_images_volume_group':
    path              => '/etc/nova/nova.conf',
    key_val_separator => '=',    
    section           => 'DEFAULT',
    setting           => 'libvirt_images_volume_group',
    value             => 'instance-volumes',
    ensure            => present,
    require           => File['/etc/nova/nova.conf'],
    notify            => Service['nova-compute'],
  }

}