class role_openstack::control(

  $admin_password,
  $rabbit_password,
  $keystone_db_password,
  $keystone_admin_token,
  $glance_db_password,
  $glance_user_password,
  $nova_db_password,
  $nova_user_password,
  $secret_key,
  $mysql_root_password,
  $neutron_user_password,
  $neutron_db_password,
  $neutron_shared_secret,
  $cinder_db_password,
  $cinder_user_password,
  $swift_user_password,


  $lvm_volume_disks = [],
  $ceph_fsid        = 'false',
  $rbd_secret_uuid  = 'bdd68f4b-fdab-4bdd-8939-275bc9ac3472',
  $admin_email      = 'aut@naturalis.nl',
  $region           = 'Leiden'

){
  

  if $ceph_fsid != 'false'{
    file {'/etc/ceph':
      ensure => directory,
    }

    Ini_setting <<| tag == "cephconf-${$ceph_fsid}" |>> {
      require => File['/etc/ceph'],
    }

    class { 'role_openstack::ceph::package': }

  }

  #configure eth1 to be up
  file {'/etc/network/interfaces':
    ensure    => present,
    mode      => '0644',
    content   => template('role_openstack/interfaces.erb')
  }

  exec {'set interface eth1 to up':
    command   => '/sbin/ifconfig eth1 up',
    unless    => '/sbin/ifconfig | /bin/grep eth1',
    require   => File['/etc/network/interfaces']
  }

  if size($lvm_volume_disks) < 1 {
    #do not use local storage for glance/cinder
    notice('not using local storage for cinder/glace')
  }else{
    # do use local storage for glance/cinder
    
    physical_volume { $lvm_volume_disks:
      ensure => present,
      #unless_vg => 'cinder-volumes',
      #no before is needed because is it hardcoded in the lvm module
    }

    volume_group {'cinder-volumes':
      ensure            => present,
      physical_volumes  => $lvm_volume_disks,
      #createonly => true,
      before            => Class['openstack::repo'],
    }
  }
  
  class {'openstack::repo': 
#    before => Exec['apt-get-update after repo addition']
  } ~>

  exec {'apt-get-update after repo addition':
    command => '/usr/bin/apt-get update',
#    before => Class['openstack::controller'],
  }


  #just make sure apt-get update is run before everyting else
  Exec['apt-get-update after repo addition'] -> Class['keystone::db::mysql'] 
  Exec['apt-get-update after repo addition'] -> Class['glance::db::mysql']
  Exec['apt-get-update after repo addition'] -> Class['nova::db::mysql']
  Exec['apt-get-update after repo addition'] -> Class['cinder::db::mysql']
  Exec['apt-get-update after repo addition'] -> Class['neutron::db::mysql']

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

  Class['keystone::db::mysql'] -> Class['keystone']
  Class['keystone::db::mysql'] -> Class['keystone::roles::admin']
  Class['keystone::db::mysql'] -> Class['keystone::endpoint']

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
    public_address   => $::ipaddress_eth0,
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
    cache_server_ip       => '127.0.0.1',
    cache_server_port     => '11211',
    secret_key            => $secret_key,
    keystone_url          => 'http://127.0.0.1:5000/v2.0',
    django_debug          => 'False',
    api_result_limit      => 1000,
  }

  ########################################


  #########     GLANCE    ################
  
  Class['glance::db::mysql'] -> Class['glance::api']
  Class['glance::db::mysql'] -> Class['glance::registry']
  Class['glance::db::mysql'] -> Class['glance::backend::rbd']

  class { 'glance::db::mysql':
      user          => 'glance',
      password      => $glance_db_password,
      dbname        => 'glance',
      allowed_hosts => '%',
      charset       => 'latin1',
  }

  class { 'glance::keystone::auth':
        password         => $glance_user_password,
        public_address   => $::ipaddress_eth0,
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

  class { 'glance::backend::rbd':
      rbd_store_user => 'glance',
      rbd_store_pool => 'images',
  }

  ########################################

  #########      NOVA     ################

  Class['nova::db::mysql'] -> Class['nova']
  Class['nova::db::mysql'] -> Class['nova::rabbitmq']
  Class['nova::db::mysql'] -> Class['nova::api']
  Class['nova::db::mysql'] -> Class['nova::network::neutron']
  Class['nova::db::mysql'] -> Class['nova::vncproxy']

  class { 'nova::db::mysql':
      user          => 'nova',
      password      => $nova_db_password,
      dbname        => 'nova',
      allowed_hosts => '%',
      charset       => 'latin1',
  }
  
  class { 'nova::keystone::auth':
        password         => $nova_user_password,
        public_address   => $::ipaddress_eth0,
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
      region                    => $region,
  }

  class { ['nova::scheduler','nova::objectstore','nova::cert','nova::consoleauth','nova::conductor']:
    enabled => true,
  }

  class { 'nova::vncproxy':
      host    => $::ipaddress_eth0,
      enabled => true,
  }


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

  #cinder part
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
          Class[cinder::volume::rbd]
        ],
  }

  class { 'cinder::keystone::auth':
        password         => $cinder_user_password,
        public_address   => $::ipaddress_eth0,
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

  class { 'cinder::volume::rbd':
          rbd_pool        => 'volumes',
          rbd_user        => 'cinder',
          rbd_secret_uuid => $rbd_secret_uuid,
  }



 
  #neutron part.
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
          Class[neutron::keystone::auth],
          Class[neutron::agents::vpnaas]
        ],
  }

  class { 'neutron::keystone::auth':
        password         => $neutron_user_password,
        public_address   => $::ipaddress_eth0,
        public_protocol  => 'http',
        admin_address    => $::ipaddress_eth0,
        internal_address => $::ipaddress_eth0,
        region           => $region,
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
#      auth_url       => 'http://127.0.0.1:35357/v2.0',
      auth_url       => 'http://127.0.0.1:5000/v2.0',
      auth_region    => $region,
      debug          => true,
  }

  class { 'neutron::agents::dhcp':
      use_namespaces => true,
      debug          => false,
  }

  class { 'neutron::agents::l3':
      use_namespaces => true,
      debug          => false,
  }

  class { 'neutron::agents::vpnaas': }
  
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
}