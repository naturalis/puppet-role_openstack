class role_openstack::control(

){
  class {'openstack::control':
# Required Network
  public_address => $::ipaddress_eth0,
  admin_email => 'aut@naturalis.nl',
# required password
  admin_password => 'Openstack_123',
  rabbit_password => 'Openstack_123',
  keystone_db_password => 'Openstack_123',
  keystone_admin_token => 'Openstack_123',
  glance_db_password => 'Openstack_123',
  glance_user_password => 'Openstack_123',
  nova_db_password => 'Openstack_123',
  nova_user_password => 'Openstack_123',
  secret_key => 'Openstack_123',
  mysql_root_password => 'Openstack_123',
# cinder and neutron password are not required b/c they are
# optional. Not sure what to do about this.
  neutron_user_password  => 'Openstack_123',
  neutron_db_password    => 'Openstack_123',
  neutron_core_plugin    => 'neutron.plugins.openvswitch.ovs_neutron_plugin.OVSNeutronPluginV2',
  cinder_user_password   => 'Openstack_123',
  cinder_db_password     => 'Openstack_123',
  swift_user_password    => 'Openstack_123',
# Database
  db_host => '127.0.0.1',
  db_type => 'mysql',
  mysql_account_security => true,
  mysql_bind_address => '0.0.0.0',
  sql_idle_timeout => undef,
  allowed_hosts => '%',
  mysql_ssl => false,
  mysql_ca => undef,
  mysql_cert => undef,
  mysql_key => undef,
# Keystone
  keystone_host => '127.0.0.1',
  keystone_db_user => 'keystone',
  keystone_db_dbname => 'keystone',
  keystone_admin_tenant => 'admin',
  keystone_bind_address => '0.0.0.0',
  region => 'RegionOne',
  public_protocol => 'http',
  keystone_token_driver => 'keystone.token.backends.sql.Token',
  token_format => 'PKI',
# Glance
  glance_registry_host => '0.0.0.0',
  glance_db_user => 'glance',
  glance_db_dbname => 'glance',
  glance_api_servers => undef,
  glance_backend => 'file',
  glance_rbd_store_user => undef,
  glance_rbd_store_pool => undef,
# Glance Swift Backend
  swift_store_user => 'swift_store_user',
  swift_store_key => 'swift_store_key',
# Nova
  nova_admin_tenant_name => 'services',
  nova_admin_user => 'nova',
  nova_db_user => 'nova',
  nova_db_dbname => 'nova',
  purge_nova_config => false,
  enabled_apis => 'ec2,osapi_compute,metadata',
  nova_bind_address => '0.0.0.0',
# Nova Networking
  public_interface => 'eth0',
  private_interface => 'eth1',
  internal_address => false,
  admin_address => false,
  network_manager => 'nova.network.manager.FlatDHCPManager',
  fixed_range => '10.0.0.0/24',
  floating_range => false,
  create_networks => true,
  num_networks => 1,
  multi_host => true,
  auto_assign_floating_ip => false,
  network_config => {},
# Rabbit
  rabbit_host => '127.0.0.1',
  rabbit_hosts => false,
  rabbit_cluster_nodes => false,
  rabbit_user => 'openstack',
  rabbit_virtual_host => '/',
# Horizon
  horizon => true,
  cache_server_ip => '127.0.0.1',
  cache_server_port => '11211',
  horizon_app_links => undef,
# VNC
  vnc_enabled => true,
  vncproxy_host => false,
# General
  debug => false,
  verbose => false,
# cinder
# if the cinder management components should be installed
  cinder => true,
  cinder_db_user => 'cinder',
  cinder_db_dbname => 'cinder',
  cinder_bind_address => '0.0.0.0',
  manage_volumes => true,
  volume_group => 'cinder-volumes',
  setup_test_volume => true,
  iscsi_ip_address => '127.0.0.1',
# Neutron
  neutron => true,
  physical_network => 'default',
  tenant_network_type => 'gre',
  ovs_enable_tunneling => true,
  allow_overlapping_ips => true,
# ovs_local_ip false means internal address which by default is public address
  ovs_local_ip => false,
  network_vlan_ranges => undef,
  bridge_interface => 'eth0',
  external_bridge_name => 'br-ex',
  bridge_uplinks => undef,
  bridge_mappings => undef,
  enable_ovs_agent => true,
  enable_dhcp_agent => true,
  enable_l3_agent => true,
  enable_metadata_agent => true,
  metadata_shared_secret => 'neutron',
  firewall_driver => 'neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver',
  neutron_db_user => 'neutron',
  neutron_db_name => 'neutron',
  neutron_auth_url => 'http://127.0.0.1:35357/v2.0',
  enable_neutron_server => true,
  security_group_api => 'neutron',
# swift
  swift => false,
  swift_public_address => false,
  swift_internal_address => false,
  swift_admin_address => false,
# Syslog
  use_syslog => false,
  log_facility => 'LOG_USER',
  enabled => true

  }
}