=head1 XML::Descent Tutorial

As I gather more usage examples, hints and tips they'll appear here. For now as an example, here's a complete
parser for GPX 1.0 and 1.1

    sub _parse {
        my $self = shift;
        my $xml  = shift;

        my $p = XML::Descent->new({ Input => \$xml });
    
        $p->on(gpx => sub {
            my ($elem, $attr) = @_;

            $p->context($self);

            my $version = $self->{version} = $attr->{version};
        
            my $parse_deep = sub {
                my ($elem, $attr) = @_;
                my $ob = $attr;     # Get attributes
                $p->context($ob);
                $p->walk();
                return $ob;
            };

            # Parse a point
            my $parse_point = sub {
                my ($elem, $attr) = @_;
                my $pt = $parse_deep->($elem, $attr);
                return $self->{handler}->{create}->(%{$pt});
            };

            $p->on('*' => sub {
                my ($elem, $attr, $ctx) = @_;
                $ctx->{$elem} = _trim($p->text());
            });
        
            $p->on(time => sub {
                my ($elem, $attr, $ctx) = @_;
                my $tm = str2time(_trim($p->text()));
                $ctx->{$elem} = $tm if defined($tm);
            });

            if (_cmp_ver($version, '1.1') >= 0) {
                # Handle 1.1 metadata
                $p->on(metadata => sub {
                    $p->walk();
                });
                $p->on(['link', 'email', 'author'] => sub {
                    my ($elem, $attr, $ctx) = @_;
                    $ctx->{$elem} = $parse_deep->($elem, $attr);
                });
            } else {
                # Handle 1.0 metadata
                $p->on(url => sub {
                    my ($elem, $attr, $ctx) = @_;
                    $ctx->{link} ||= { };
                    $ctx->{link}->{href} = _trim($p->text());
                });
                $p->on(urlname => sub {
                    my ($elem, $attr, $ctx) = @_;
                    $ctx->{link} ||= { };
                    $ctx->{link}->{text} = _trim($p->text());
                });
                $p->on(author => sub {
                    my ($elem, $attr, $ctx) = @_;
                    $ctx->{author} ||= { };
                    $ctx->{author}->{name} = _trim($p->text());
                });
                $p->on(email => sub {
                    my ($elem, $attr, $ctx) = @_;
                    my $em = _trim($p->text());
                    if ($em =~ m{^(.+)\@(.+)$}) {
                        $ctx->{author} ||= { };
                        $ctx->{author}->{email} = {
                            id      => $1,
                            domain  => $2
                        };
                    }
                });
            }
        
            $p->on(bounds => sub {
                my ($elem, $attr, $ctx) = @_;
                $ctx->{$elem} = $parse_deep->($elem, $attr);
            });
        
            $p->on(keywords => sub {
                my ($elem, $attr) = @_;
                $self->{keywords} = [ 
                    map { _trim($_) } split(/,/, $p->text()) 
                ];
            });
    
            # Parse a waypoint
            $p->on(wpt => sub {
                my ($elem, $attr) = @_;
                push @{$self->{waypoints}}, $parse_point->($elem, $attr);
            });
        
            $p->on(['trkpt', 'rtept'] => sub {
                my ($elem, $attr, $ctx) = @_;
                push @{$ctx->{points}}, $parse_point->($elem, $attr);
            });
    
            # Parse a route
            $p->on(rte => sub {
                my ($elem, $attr) = @_;
                my $rt = $parse_deep->($elem, $attr);
                push @{$self->{routes}}, $rt;
            });

            # Parse a track
            $p->on(trk => sub {
                my ($elem, $attr) = @_;
                my $tk = { };
                $p->context($tk);
                $p->on(trkseg => sub {
                    my ($elem, $attr) = @_;
                    my $seg = $parse_deep->($elem, $attr);
                    push @{$tk->{segments}}, $seg;
                });
                $p->walk();
                push @{$self->{tracks}}, $tk;
            });

            $p->walk();
        });
    
        $p->walk();
    }

(taken from L<Geo::Gpx>)
