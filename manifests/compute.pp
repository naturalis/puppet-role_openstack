class role_openstack::compute(
  $instance_storage_disks = [],
  $libvirt_type = 'qemu',
  $volume_backend = 'lvm',
  $ceph_fsid = 'false',
  $ceph_cinder_key = 'AQCv7Q1T+FPiMBAAQ5qdQr/aQ+nNg7PRRV7S6g==',
  $cinder_rbd_secret_uuid = 'bdd68f4b-fdab-4bdd-8939-275bc9ac3472',

){
  
  if $ceph_fsid != 'false' {
    file {'/etc/ceph':
      ensure => directory,
    }

    Ini_setting <<| tag == "cephconf-${$ceph_fsid}" |>> {
      require => File['/etc/ceph'],
    }

    class { 'role_openstack::ceph::package': }

    file {'/etc/ceph/ceph.client.cinder.keyring':
      ensure => present,
      content => template('role_openstack/ceph.client.cinder.keyring.erb'),
    } ~>
    
    file {'/tmp/secret.xml':
      ensure => present,
      content => template('role_openstack/secret.xml.erb')
    } ~>

    exec {'define secret':
      command => '/usr/bin/virsh secret-define --file /tmp/secret.xml',
    #  require => File['/tmp/secret.xml'],
    } ~>

    exec {'set secret value':
      command => "/usr/bin/virsh secret-set-value --secret ${cinder_rbd_secret_uuid} --base64 \$(/bin/cat /etc/ceph/ceph.client.cinder.keyring)",
     # require => [File['/etc/ceph/ceph.client.cinder.keyring'],Exec['define secret']],
      notify => Service['nova-compute'],
    }



  }

  if size($instance_storage_disks) < 1 {
    fail('instance storage disks cannot be an empty array')
  }

  physical_volume { $instance_storage_disks:
    ensure => present,
    #unless_vg => 'instance-volumes',
    #no before is needed because is it hardcoded in the lvm module
  }

  volume_group {'instance-volumes':
    ensure => present,
    physical_volumes => $instance_storage_disks,
    #create_only => true,
    before => Class['openstack::repo'],
  }

  
  class {'openstack::repo': 
#    before => Exec['apt-get-update after repo addition']
  } ->

  exec {'apt-get-update after repo addition':
    command => '/usr/bin/apt-get update',
    unless => '/usr/bin/test -f /etc/apt/sources.list.d/ubuntu-cloud-archive.list',
 #   before => Class['openstack::compute'],
  } ->

  class {'openstack::compute':
  	 # Required Network
    internal_address => $::ipaddress_eth0,
  # Required Nova
    nova_user_password => 'Openstack_123',
  # Required Rabbit
    rabbit_password => 'Openstack_123',
  # DB
    nova_db_password => 'Openstack_123',
    db_host => '10.61.2.69',
  # Nova Database
    nova_db_user => 'nova',
    nova_db_name => 'nova',
  # Network
    public_interface => 'eth0',
    private_interface => 'eth1',
    fixed_range => undef,
    network_manager => 'nova.network.manager.FlatDHCPManager',
    network_config => {},
    multi_host => true,
    enabled_apis => 'ec2,osapi_compute,metadata',
  # Neutron
    neutron => true,
    neutron_user_password => 'Openstack_123',
    neutron_admin_tenant_name => 'services',
    neutron_admin_user => 'neutron',
    enable_ovs_agent => true,
    enable_l3_agent => false,
    enable_dhcp_agent => false,
    neutron_auth_url => 'http://10.61.2.69:35357/v2.0',
    keystone_host => '10.61.2.69',
    neutron_host => '10.61.2.69',
    ovs_enable_tunneling => true,
    ovs_local_ip => $::ipaddress_eth0,
    neutron_firewall_driver => false,
    bridge_mappings => undef,
    bridge_uplinks => undef,
    security_group_api => 'neutron',
  # Nova
    nova_admin_tenant_name => 'services',
    nova_admin_user => 'nova',
    purge_nova_config => false,
    libvirt_vif_driver => 'nova.virt.libvirt.vif.LibvirtGenericVIFDriver',
  # Rabbit
    rabbit_host => '10.61.2.69',
    rabbit_hosts => false,
    rabbit_user => 'openstack',
    rabbit_virtual_host => '/',
  # Glance
    glance_api_servers => '10.61.2.69:9292',
  # Virtualization
    libvirt_type => 'qemu',
  # VNC
    vnc_enabled => true,
    vncproxy_host => '10.61.2.69',
    vncserver_listen => false,
  # cinder / volumes
  # manage_volumes => true, 
    manage_volumes => false,
    cinder_volume_driver => 'iscsi',
    cinder_db_password => 'Openstack_123',
    cinder_db_user => 'cinder',
    cinder_db_name => 'cinder',
    volume_group => 'cinder-volumes',
    iscsi_ip_address => '10.61.2.69',
    setup_test_volume => false,
    cinder_rbd_user => 'volumes',
    cinder_rbd_pool => 'volumes',
    cinder_rbd_secret_uuid => false,
  # General
    migration_support => false,
    verbose => false,
    force_config_drive => false,
   # use_syslog => false,
   # log_facility => 'LOG_USER',
    enabled => true,
  }
  
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