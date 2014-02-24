class role_openstack::compute(
  $libvirt_type = 'qemu',
){
  
  class {'openstack::repo':
    before => Class['openstack::compute'],
  }

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
    manage_volumes => true,
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
    value             => 'cinder-volumes',
    ensure            => present,
    require           => File['/etc/nova/nova.conf'],
    notify            => Service['nova-compute'],
  }
}