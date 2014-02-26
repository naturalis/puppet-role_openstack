class role_openstack::ceph::package(
  $ceph_release = 'emperor'
)
{

	# JOBS #
	# * install ceph packages
  package { 'wget':
    ensure => installed,
  }
  
  exec { 'add-ceph-repo-key':
  	command => "/usr/bin/wget -q -O- 'https://ceph.com/git/?p=ceph.git;a=blob_plain;f=keys/release.asc' | sudo apt-key add -",
  	require => Package ['wget'],
    unless   => "/usr/bin/apt-key list | grep Ceph"
  }
  
  exec { 'add-ceph-repo':
    command => "/bin/echo deb http://ceph.com/debian-${ceph_release}/ $(lsb_release -sc) main | sudo tee /etc/apt/sources.list.d/ceph.list",
    require => Exec['add-ceph-repo-key'],
    unless  => "/bin/grep ${ceph_release} /etc/apt/sources.list.d/ceph.list"
  }

  exec { 'update-apt-get':
    command => '/usr/bin/apt-get update',
    require => Exec['add-ceph-repo']
  }
  
  package { 'ceph-common':
    ensure => installed,
    require => Exec['update-apt-get']
  }
  
}