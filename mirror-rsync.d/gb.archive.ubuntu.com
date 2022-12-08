#This file is dot-sourced so use bash syntax!
name='ubuntu'
releases=('jammy' 'jammy-updates' 'jammy-backports')
repositories=('main' 'restricted' 'universe' 'multiverse')
architectures=('i386' 'amd64')
