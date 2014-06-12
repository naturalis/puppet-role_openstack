#
#
#
class role_openstack::compute::testcompute(

  $nova_user_password,
  $rabbit_password,
  $nova_db_password,
  $control_ip_address,
  $neutron_user_password,

  $openstack_cluster_id,

  $image_cache_size_gb  = 40,

  $instance_volume_device = '/dev/sdc',

  $libvirt_type         = 'kvm',
  $region               = 'Arrakis',



){

  stage { 'pre': }

  Stage['pre'] -> Stage['main']

  class {'role_openstack::compute::prepare':
    openstack_cluster_id    => $openstack_cluster_id,
    instance_volume_device  => $instance_volume_device,
    image_cache_size_gb     => $image_cache_size_gb,
    stage                   => 'pre'
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
