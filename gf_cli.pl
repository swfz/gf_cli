#!/usr/bin/env perl
# delete graph if not exists config

use warnings;
use strict;
use Net::GrowthForecast;
use YAML::XS;
use Data::Dumper;
use Getopt::Long qw(:config auto_help);
use Pod::Usage;

my $options = {};
my @args_pattern= ( 'mode=s' );
GetOptions( $options, @args_pattern ) or pod2usage( verbose => 1 );
pod2usage( verbose => 1) unless keys %$options;

my $config  = YAML::XS::LoadFile('config.yml');
my $host    = $config->{ host } . $config->{ prefix };
my $gf      = Net::GrowthForecast->new( host => $host, port => $config->{ port } );
my $service = $config->{ target_service };

main();

sub main {
  if ( $options->{ mode } eq 'delete' ) {
    my $exception_graphs = exception_graphs();
    map { print $_->{ section_name } . "/". $_->{ graph_name } . "\n" } @$exception_graphs;

    my $answer = "";
    while ( $answer ne 'yes' and $answer ne 'no' ) {
      print "delete target:" . scalar @$exception_graphs . ". yes or no? :";
      chomp( $answer = <STDIN> );
      if ( $answer eq 'yes' ) {
        delete_exception_graphs( $exception_graphs ) if scalar @$exception_graphs > 0;
      }
    }
  }
  elsif ( $options->{ mode } eq 'list' ) {
    graph_list();
  }
  elsif ( $options->{ mode } eq 'complex' ) {
    create_complex();
  }
}

sub delete_exception_graphs {
  my $graphs = shift;

  my $result = {};
  foreach my $graph ( @$graphs ) {
    $result->{ $graph->{ section_name } . "/" . $graph->{ graph_name } } = $gf->delete( $graph );
  }

  warn Dumper $result;
}

sub exception_graphs {
  my $service_graphs = graph_list();

  my $exception_graphs = [];
  foreach my $target ( @$service_graphs ) {
    my $expect_is_exists = 0;

    # check fixed graphs
    foreach my $expect ( @{ $config->{ expect_fixed_graphs } } ) {
      if ( $target->{ section_name } eq $expect->{ section } && $target->{ graph_name } eq $expect->{ graph } ) {
        $expect_is_exists = 1;
        last;
      }
    }
    # check server graphs
    foreach my $expect ( @{ $config->{ expect_server_graphs } } ) {
      if ( $target->{ section_name } =~ /^ip-[0-9]+-[0-9]+-[0-9]+-[0-9]+\.$expect->{ section }/ && $target->{ graph_name } eq $expect->{ graph } ) {
        $expect_is_exists = 1;
        last;
      }
    }

    push @$exception_graphs, $target unless $expect_is_exists;
  }

  warn "exception graphs: " . scalar @$exception_graphs. "/" . scalar @$service_graphs;
  return $exception_graphs;
}

sub graph_list {
  my $graphs = $gf->all();
  my @service_graphs = grep { $_->{ service_name } eq $config->{ target_service } } @$graphs;
  warn scalar @service_graphs . " graphs in " . $service;
  return \@service_graphs;
}

sub create_complex {
  my $graph_ids;

  my $graphs = graph_list();
  foreach my $graph ( @$graphs ) {
    my $host = $graph->{ section_name };
    my $name = $graph->{ graph_name };
    $name =~ s/\..*//;
    push @{ $graph_ids->{ $host }->{ $name } }, $graph->{ id } if $graph->{ service_name } eq $service;
  }

  my $result = [];
  foreach my $host ( keys %$graph_ids ) {
    foreach my $item ( keys %{ $graph_ids->{ $host } } ) {
      push @$result, create_line( $host, $item, $graph_ids->{ $host }->{ $item } ) if $item =~ m/load avg.*/ or $item =~ m/dsk_total.*/ or $item =~ m/io_total.*/;
      push @$result, create_area( $host, $item, $graph_ids->{ $host }->{ $item } ) if $item =~ m/swap.*/ or $item =~ m/memory.*/ or $item =~ m/total cpu usage.*/;
    }
  }
  warn Dumper $result;
}

sub create_area {
  my ( $host, $item, $ids )= @_;

  $gf->add_complex(
    "$service",
    "$host",
    "complex $item",
    "complex area",
    1,       #sumup
    19,      #sort
    "AREA",  #type AREA/LINE1
    "gauge", #gmode gauge/subtract
    1,       #stack
    @$ids
  );
}

sub create_line {
  my ( $host, $item, $ids )= @_;

  $gf->add_complex(
    "$service",
    "$host",
    "complex $item",
    "complex line",
    1,       #sumup
    19,      #sort
    "LINE1", #type AREA/LINE1/LINE2
    "gauge", #gmode gauge/subtract
    0,       #stack
    @$ids
  );
}

=head1 SYNOPSIS

todo.pl [options]

Options:

  --help

  --mode  (list|complex|delete)

=cut


