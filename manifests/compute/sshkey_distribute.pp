class role_openstack::compute::sshkey_distribute(
  $export_tag,

){
  
  file { "${fqdn}-facter-base-dir":
    path   => "/etc/facter",
    ensure => "directory",
  }

  file { "${fqdn}-facter-sub-dir":
    path    => "/etc/facter/facts.d",
    ensure  => "directory",
    require => File["${fqdn}-facter-base-dir"]
  }

  exec {"${::fqdn}-generate-sshkey":
    command => "/bin/su -s '/bin/bash' -c '/usr/bin/ssh-keygen -b 2048 -t rsa -f /var/lib/nova/.ssh/id_rsa -q -N \"\"' nova",
    creates => '/var/lib/nova/.ssh/id_rsa.pub',
    require => File['/var/lib/nova'],
  }

  
  exec {"${::fqdn}-fact-pub-sshkey":
    command => '/bin/echo nova_pub_sshkey=$(/bin/cat /var/lib/nova/.ssh/id_rsa.pub) > /etc/facter/facts.d/nova_pub_sshkey.txt',
    creates => '/etc/facter/facts.d/nova_pub_sshkey.txt',
    require => Exec["${::fqdn}-generate-sshkey"],
  }


  if ($::nova_pub_sshkey) {
    @@exec {"${::fqdn}-add-pub-key":
      command => "/bin/echo ${::nova_pub_sshkey} >> /var/lib/nova/.ssh/authorized_keys",
      #creates => '/var/lib/nova/.ssh/authorized_keys',
      unless  => "/bin/cat /var/lib/nova/.ssh/authorized_keys | /bin/grep ${::nova_pub_sshkey}", 
      require => File['/var/lib/nova'],
      tag     => $export_tag,
    }
  }

}