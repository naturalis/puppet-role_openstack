class role_openstack::control::stackinstance(


  $openstack_cluster_id,

  $admin_password         = 'test',
  $rabbit_password        = 'test',
  $keystone_db_password   = 'test',
  $keystone_admin_token   = 'test',
  $glance_db_password     = 'test',
  $glance_user_password   = 'test',
  $nova_db_password       = 'test',
  $nova_user_password     = 'test',
  $secret_key             = 'test',
  $mysql_root_password    = 'test',
  $neutron_user_password  = 'test',
  $neutron_db_password    = 'test',
  $neutron_shared_secret  = 'test',
  $cinder_db_password     = 'test',
  $cinder_user_password   = 'test',

  $public_address         = 'localhost',
  $image_cache_size_gb    = 50,

  $lvm_volume_disks       = '/dev/sdc',
  $admin_email            = 'aut@naturalis.nl',
  $region                 = 'Arrakis',

  $neutron_lbaas          = false,
  $neutron_vpnaas         = false,
  $neutron_fwaas          = false,

){

  stage { 'pre': }

  Stage['pre'] -> Stage['main']

  class {'::role_openstack::control::prepare':
    lvm_volume_disks  => $lvm_volume_disks,
    stage             => 'pre',
  }


  ###########    MYSQL   #################

  class { 'mysql::server':
    config_hash => {
      'root_password' => $mysql_root_password,
      'bind_address'  => '0.0.0.0',
    },
    enabled     => true,
  }

  class { 'mysql::server::account_security': }


  ########################################

  #########    KEYSTONE   ################

  # Class['keystone::db::mysql'] -> Class['keystone']
  # Class['keystone::db::mysql'] -> Class['keystone::roles::admin']
  # Class['keystone::db::mysql'] -> Class['keystone::endpoint']

  class { 'keystone::db::mysql':
      user          => 'keystone',
      password      => $keystone_db_password,
      dbname        => 'keystone',
      allowed_hosts => '%',
      charset       => 'latin1',
  }

  class { 'keystone':
    debug          => false,
    bind_host      => '0.0.0.0',
    catalog_type   => 'sql',
    admin_token    => $keystone_admin_token,
    token_driver   => 'keystone.token.backends.sql.Token',
    token_format   => 'PKI',
    enabled        => true,
    sql_connection => "mysql://keystone:${keystone_db_password}@127.0.0.1/keystone?charset=latin1",
  }

  class { 'keystone::roles::admin':
      email        => $admin_email,
      password     => $admin_password,
      admin_tenant => 'admin',
  }

    # Setup the Keystone Identity Endpoint
  class { 'keystone::endpoint':
    public_address   => $public_address,
    public_protocol  => 'http',
    admin_address    => $::ipaddress_eth0,
    internal_address => $::ipaddress_eth0,
    region           => $region,
  }

  ########################################

  #########    HORIZON   ################

  class { 'memcached':
      listen_ip => '127.0.0.1',
      tcp_port  => '11211',
      udp_port  => '11211',
  }

  class { 'horizon':
    fqdn                    => [$::fqdn,$public_address,$::hostname,$::ipaddress_eth0,'openstack'],
    cache_server_ip         => '127.0.0.1',
    cache_server_port       => '11211',
    secret_key              => $secret_key,
    keystone_url            => 'http://127.0.0.1:5000/v2.0',
    django_debug            => 'False',
    api_result_limit        => 1000,
    help_url                => 'http://docs.openstack.org',
    local_settings_template => 'role_openstack/local_settings-teststack.py.erb',
    neutron_options         => {
      'enable_lb'             => $neutron_lbaas,
      'enable_firewall'       => $neutron_fwaas,
      'enable_quotas'         => true,
      'enable_security_group' => true,
      'enable_vpn'            => $neutron_vpnaas,
      'profile_support'       => 'None'
    },
  }


  ########################################


  #########     GLANCE    ################

  # Class['glance::db::mysql'] -> Class['glance::api']
  # Class['glance::db::mysql'] -> Class['glance::registry']
  # Class['glance::db::mysql'] -> Class['glance::backend::file']

  class { 'glance::db::mysql':
      user          => 'glance',
      password      => $glance_db_password,
      dbname        => 'glance',
      allowed_hosts => '%',
      charset       => 'latin1',
  }

  class { 'glance::keystone::auth':
        password         => $glance_user_password,
        public_address   => $public_address,
        public_protocol  => 'http',
        admin_address    => $::ipaddress_eth0,
        internal_address => $::ipaddress_eth0,
        region           => $region,
  }

  class { 'glance::api':
    debug             => false,
    auth_type         => 'keystone',
    auth_port         => '35357',
    auth_host         => '127.0.0.1',
    keystone_tenant   => 'services',
    keystone_user     => 'glance',
    keystone_password => $glance_user_password,
    sql_connection    => "mysql://glance:${glance_db_password}@127.0.0.1/glance?charset=latin1",
    enabled           => true,
  }

  class { 'glance::registry':
    debug             => false,
    auth_host         => '127.0.0.1',
    auth_port         => '35357',
    auth_type         => 'keystone',
    keystone_tenant   => 'services',
    keystone_user     => 'glance',
    keystone_password => $glance_user_password,
    sql_connection    => "mysql://glance:${glance_db_password}@127.0.0.1/glance?charset=latin1",
    enabled           => true,
  }

  class { 'glance::backend::file': }

  ########################################

  #########      NOVA     ################

  # Class['nova::db::mysql'] -> Class['nova']
  # Class['nova::db::mysql'] -> Class['nova::rabbitmq']
  # Class['nova::db::mysql'] -> Class['nova::api']
  # Class['nova::db::mysql'] -> Class['nova::network::neutron']
  # Class['nova::db::mysql'] -> Class['nova::vncproxy']

  class { 'nova::db::mysql':
      user          => 'nova',
      password      => $nova_db_password,
      dbname        => 'nova',
      allowed_hosts => '%',
      charset       => 'latin1',
  }

  class { 'nova::keystone::auth':
        password         => $nova_user_password,
        public_address   => $public_address,
        public_protocol  => 'http',
        admin_address    => $::ipaddress_eth0,
        internal_address => $::ipaddress_eth0,
        region           => $region,
  }

  class { 'nova::rabbitmq':
    userid                 => 'openstack',
    password               => $rabbit_password,
    enabled                => true,
    virtual_host           => '/',
  }

  class { 'nova':
    sql_connection       => "mysql://nova:${nova_db_password}@127.0.0.1/nova?charset=latin1",
    rabbit_userid        => 'openstack',
    rabbit_password      => $rabbit_password,
    rabbit_virtual_host  => '/',
    image_service        => 'nova.image.glance.GlanceImageService',
    glance_api_servers   => "${::ipaddress_eth0}:9292",
    debug                => false,
    rabbit_host          => '127.0.0.1',
  }

  class { 'nova::api':
    enabled                              => true,
    admin_tenant_name                    => 'services',
    admin_user                           => 'nova',
    admin_password                       => $nova_user_password,
    enabled_apis                         => 'ec2,osapi_compute,metadata',
    api_bind_address                     => '0.0.0.0',
    auth_host                            => '127.0.0.1',
    neutron_metadata_proxy_shared_secret => $neutron_shared_secret,
  }

  class { 'nova::network::neutron':
      neutron_admin_password    => $neutron_user_password,
      neutron_auth_strategy     => 'keystone',
      neutron_url               => "http://127.0.0.1:9696",
      neutron_admin_tenant_name => 'services',
      neutron_admin_username    => 'neutron',
      neutron_admin_auth_url    => "http://127.0.0.1:35357/v2.0",
      security_group_api        => 'neutron',
      neutron_region_name       => $region,
  }

  class { ['nova::scheduler','nova::objectstore','nova::cert','nova::consoleauth','nova::conductor']:
    enabled => true,
  }

  class { 'nova::vncproxy':
      host    => $::ipaddress_eth0,
      enabled => true,
  }

  #class { 'nova::spicehtml5proxy':
  #  enabled        => true,
  #  host           => '0.0.0.0',
  #  port           => '6082',
  #  ensure_package => 'present',
  #}

  ########################################

  #########     CINDER    ################

  class { 'cinder::db::mysql':
        user          => 'cinder',
        password      => $cinder_db_password,
        dbname        => 'cinder',
        allowed_hosts => '%',
        charset       => 'latin1',
        before        => [
          Class[cinder::keystone::auth],
          Class[cinder],
          Class[cinder::api],
          Class[cinder::scheduler],
          Class[cinder::volume],
          Class[cinder::volume::iscsi]
        ],
  }

  class { 'cinder::keystone::auth':
        password         => $cinder_user_password,
        public_address   => $public_address,
        admin_address    => $::ipaddress_eth0,
        public_protocol  => 'http',
        internal_address => $::ipaddress_eth0,
        region           => $region,
  }


  class {'cinder':
    sql_connection      => "mysql://cinder:${cinder_db_password}@127.0.0.1/cinder?charset=latin1",
    rabbit_userid       => 'openstack',
    rabbit_password     => $rabbit_password,
    rabbit_host         => '127.0.0.1',
    rabbit_virtual_host => '/',
    debug               => false,
  }

  class {'cinder::api':
    keystone_password       => $cinder_user_password,
    keystone_user           => 'cinder',
    keystone_auth_host      => '127.0.0.1',
    keystone_auth_protocol  => 'http',
    bind_host               => '0.0.0.0',
    enabled                 => true,
  }

  class {'cinder::scheduler':
    scheduler_driver       => 'cinder.scheduler.simple.SimpleScheduler',
  }

  class {'::cinder::volume': }

  class {'::cinder::volume::iscsi':
    iscsi_ip_address => $::ipaddress_eth0,
  }

  class { 'cinder::glance':
    glance_api_servers => "${::ipaddress_eth0}:9292",
  }


 ########################################

 ##########    NEUTRON    ###############

  class { 'neutron::db::mysql':
        user          => 'neutron',
        password      => $neutron_db_password,
        dbname        => 'neutron',
        allowed_hosts => '%',
        charset       => 'latin1',
        before        => [
          Class[neutron],
          Class[neutron::server],
          Class[neutron::plugins::ovs],
          Class[neutron::agents::ovs],
          Class[neutron::agents::metadata],
          Class[neutron::agents::dhcp],
          Class[neutron::agents::l3],
          Class[neutron::keystone::auth]
        ],
  }

  class { 'neutron::keystone::auth':
        password         => $neutron_user_password,
        public_address   => $public_address,
        public_protocol  => 'http',
        admin_address    => $::ipaddress_eth0,
        internal_address => $::ipaddress_eth0,
        region           => $region,
  }

  $sp_selector = "${neutron_lbaas}_${neutron_vpnaas}_${neutron_fwaas}"
  $service_plugins = $sp_selector ? {
    'false_false_false'  => undef,
    'true_false_false'   => ['neutron.services.loadbalancer.plugin.LoadBalancerPlugin'],
    'false_true_false'   => ['neutron.services.vpn.plugin.VPNDriverPlugin'],
    'true_true_false'    => ['neutron.services.loadbalancer.plugin.LoadBalancerPlugin','neutron.services.vpn.plugin.VPNDriverPlugin'],
    'false_false_true'   => ['neutron.services.firewall.fwaas_plugin.FirewallPlugin'],
    'true_false_true'    => ['neutron.services.loadbalancer.plugin.LoadBalancerPlugin','neutron.services.firewall.fwaas_plugin.FirewallPlugin'],
    'false_true_true'    => ['neutron.services.vpn.plugin.VPNDriverPlugin','neutron.services.firewall.fwaas_plugin.FirewallPlugin'],
    'true_true_true'     => ['neutron.services.loadbalancer.plugin.LoadBalancerPlugin','neutron.services.vpn.plugin.VPNDriverPlugin','neutron.services.firewall.fwaas_plugin.FirewallPlugin'],
  }

  class { 'neutron':
    enabled               => true,
    core_plugin           => 'neutron.plugins.openvswitch.ovs_neutron_plugin.OVSNeutronPluginV2',
    allow_overlapping_ips => true,
    rabbit_host           => '127.0.0.1',
    rabbit_virtual_host   => '/',
    rabbit_user           => 'openstack',
    rabbit_password       => $rabbit_password,
    debug                 => false,
    service_plugins       => $service_plugins,
  }

  class { 'neutron::server':
      auth_host           => '127.0.0.1',
      auth_password       => $neutron_user_password,
      database_connection => "mysql://neutron:${neutron_db_password}@127.0.0.1/neutron?charset=latin1",
  }

  class { 'neutron::plugins::ovs':
      sql_connection      => "mysql://neutron:${neutron_db_password}@127.0.0.1/neutron?charset=latin1",
      sql_idle_timeout    => '3600',
      tenant_network_type => 'gre',
  }

  class { 'neutron::agents::ovs':
      enable_tunneling => true,
      bridge_uplinks   => ['br-ex:eth1'],
      bridge_mappings  => ['default:br-ex'],
      local_ip         => $::ipaddress_eth0,
      firewall_driver  => 'neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver',
  }

  class { 'neutron::agents::metadata':
      auth_password  => $neutron_user_password,
      shared_secret  => $neutron_shared_secret,
      auth_url       => 'http://127.0.0.1:35357/v2.0',
#      auth_url       => 'http://127.0.0.1:5000/v2.0',
      auth_region    => $region,
      debug          => false,
  }

  class { 'neutron::agents::dhcp':
      use_namespaces => true,
      debug          => false,
  }

  class { 'neutron::agents::l3':
      use_namespaces => true,
      debug          => false,
  }

  if $neutron_lbaas == 'true' {

    class { 'neutron::agents::lbaas':
        use_namespaces => true,
        debug          => false,
    }

  }

  if $neutron_vpnaas == 'true' {

    package { 'openswan':
      ensure => installed,
    }

    package { 'neutron-plugin-vpn-agent':
      ensure => installed,
    }

    class { 'neutron::agents::vpnaas': }

    file { '/etc/neutron/rootwrap.d/vpnaas.filters' :
      ensure    => present,
      mode      => '0644',
      content   => template('role_openstack/vpnaas.filters.erb'),
      notify    => [Service['neutron-server'],Service['neutron-plugin-vpn-agent']],
    }

    ini_setting { 'neutron vpnaas interfacedriver':
      path              => '/etc/neutron/vpn_agent.ini',
      key_val_separator => '=',
      section           => 'DEFAULT',
      setting           => 'interface_driver',
      value             => 'neutron.agent.linux.interface.OVSInterfaceDriver',
      ensure            => present,
      notify            => [Service['neutron-server'],Service['neutron-plugin-vpn-agent']],
    }

    ini_setting { 'neutron vpnaas agent':
      path              => '/etc/neutron/vpn_agent.ini',
      key_val_separator => '=',
      section           => 'DEFAULT',
      setting           => 'vpn_device_driver',
      value             => 'neutron.services.vpn.device_drivers.ipsec.OpenSwanDriver',
      ensure            => present,
      notify            => [Service['neutron-server'],Service['neutron-plugin-vpn-agent']],
    }


  }

  if $neutron_fwaas == 'true' {
    class { 'neutron::services::fwaas': }
  }


  # ini_setting { 'neutron vpnaas interfacedriver':
  #   path              => '/etc/neutron/vpn_agent.ini',
  #   key_val_separator => '=',
  #   section           => 'DEFAULT',
  #   setting           => 'interface_driver',
  #   value             => 'neutron.agent.linux.interface.OVSInterfaceDriver',
  #   ensure            => present,
  #   require           => File['/etc/nova/nova.conf'],
  #   notify            => Service['nova-compute'],
  # }
########################################

  #end of neutron part

  #ini_setting { 'set_offline_compression':
  #  path    => '/etc/openstack-dashboard/local_settings.py',
  #  section => '',
  #  setting => 'COMPRESS_OFFLINE',
  #  value   => 'True',
  #  ensure  => present,
  #  require => File['/etc/openstack-dashboard/local_settings.py'],
    #notify => [Service['apache2'],Service['memcached']],
  #}

    ########################################

#   class {'openstack::controller':
#   # Required Network
#     public_address          => $::ipaddress_eth0,
#     admin_email             => 'aut@naturalis.nl',
#   # required password
#     admin_password          => $admin_password,
#     rabbit_password         => $rabbit_password,
#     keystone_db_password    => $keystone_db_password,
#     keystone_admin_token    => $keystone_admin_token,
#     glance_db_password      => $glance_db_password,
#     glance_user_password    => $glance_user_password,
#     nova_db_password        => $nova_db_password,
#     nova_user_password      => $nova_user_password,
#     secret_key              => $secret_key,
#     mysql_root_password     => $mysql_root_password,
#   # cinder and neutron password are not required b/c they are
#   # optional. Not sure what to do about this.
#     neutron_user_password   => $neutron_user_password,
#     neutron_db_password     => $neutron_db_password,
#     cinder_user_password    => $cinder_user_password,
#     cinder_db_password      => $cinder_db_password,
#     swift_user_password     => $swift_user_password,
#   # Database
#     db_host                 => '127.0.0.1',
#     db_type                 => 'mysql',
#     mysql_account_security  => true,
#     mysql_bind_address      => '0.0.0.0',
#     sql_idle_timeout        => undef,
#     allowed_hosts           => '0.0.0.0',
#     mysql_ssl               => false,
#     mysql_ca                => undef,
#     mysql_cert              => undef,
#     mysql_key               => undef,
#   # Keystone
#     keystone_host           => '127.0.0.1',
#     keystone_db_user        => 'keystone',
#     keystone_db_dbname      => 'keystone',
#     keystone_admin_tenant   => 'admin',
#     keystone_bind_address   => '0.0.0.0',
#     region                  => $region,
#     public_protocol         => 'http',
#     keystone_token_driver   => 'keystone.token.backends.sql.Token',
#     token_format            => 'PKI',
#   # Glance
#     glance_registry_host    => '0.0.0.0',
#     glance_db_user          => 'glance',
#     glance_db_dbname        => 'glance',
#     glance_api_servers      => undef,
#     glance_backend          => 'rbd',
#     glance_rbd_store_user   => 'glance',
#     glance_rbd_store_pool   => 'images',
#   # Glance Swift Backend
#     swift_store_user        => 'swift_store_user',
#     swift_store_key         => 'swift_store_key',
#   # Nova
#     nova_admin_tenant_name  => 'services',
#     nova_admin_user         => 'nova',
#     nova_db_user            => 'nova',
#     nova_db_dbname          => 'nova',
#     purge_nova_config       => false,
#     enabled_apis            => 'ec2,osapi_compute,metadata',
#     nova_bind_address       => '0.0.0.0',
#   # Nova Networking
#     public_interface        => 'eth0',
#     private_interface       => 'eth1',
#     internal_address        => $::ipaddress_eth0,
#     admin_address           => false,
#     network_manager         => 'nova.network.manager.FlatDHCPManager',
#     fixed_range             => '10.0.0.0/24',
#     floating_range          => false,
#     create_networks         => true,
#     num_networks            => 1,
#     multi_host              => true,
#     auto_assign_floating_ip => false,
#     network_config          => {},
#   # Rabbit
#     rabbit_host             => '127.0.0.1',
#     rabbit_hosts            => false,
#     rabbit_cluster_nodes    => false,
#     rabbit_user             => 'openstack',
#     rabbit_virtual_host     => '/',
#   # Horizon
#     horizon                 => true,
#     cache_server_ip         => '127.0.0.1',
#     cache_server_port       => '11211',
#     horizon_app_links       => undef,
#   # VNC
#     vnc_enabled             => true,
#     vncproxy_host           => false,
#   # General
#     debug                   => false,
#     verbose                 => false,
#   # cinder
#   # if the cinder management components should be installed
#     cinder                  => false,
# #    cinder_db_user => 'cinder',
# #    cinder_db_dbname => 'cinder',
# #    cinder_bind_address => '0.0.0.0',
# #    manage_volumes => true,
# #    volume_group => 'cinder-volumes',
# #    setup_test_volume => false,
# #    iscsi_ip_address => $::ipaddress_eth0,
#   # Neutron
#     neutron                 => false,
#   #  neutron_core_plugin     => 'neutron.plugins.openvswitch.ovs_neutron_plugin.OVSNeutronPluginV2',
#   #  physical_network        => 'default',
#   #  tenant_network_type     => 'gre',
#   #  ovs_enable_tunneling    => true,
#   #  allow_overlapping_ips   => true,
#   # ovs_local_ip false means internal address which by default is public address
#   #  ovs_local_ip            => false,
#   #  network_vlan_ranges     => undef,
#   #  bridge_interface        => 'eth1',
#   #  external_bridge_name    => 'br-ex',
#   #  bridge_uplinks          => undef,
#   #  bridge_mappings         => undef,
#   #  enable_ovs_agent        => true,
#   #  enable_dhcp_agent       => true,
#   #  enable_l3_agent         => true,
#   #  enable_metadata_agent   => true,
#   #  metadata_shared_secret  => 'neutron',
#   #  firewall_driver         => 'neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver',
#   #  neutron_db_user         => 'neutron',
#   #  neutron_db_name         => 'neutron',
#   #  neutron_auth_url        => "http://127.0.0.1:35357/v2.0",
#   #  enable_neutron_server   => true,

#   #security_group_api is used in the openstack::nova:controller class
#     security_group_api      => 'neutron',
#   # swift
#     swift                   => false,
#     swift_public_address    => false,
#     swift_internal_address  => false,
#     swift_admin_address     => false,
#   # Syslog
#     use_syslog              => false,
#     log_facility            => 'LOG_USER',
#     enabled                 => true

#   }



}
