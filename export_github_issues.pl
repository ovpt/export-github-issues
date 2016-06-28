#! /usr/bin/env perl

use strict;
use Getopt::Std;
use LWP::UserAgent;
use JSON::Parse 'parse_json';
use HTTP::Headers;
use URI;


sub usage {
    print "usage: $0 options\n";
    print "\t-t personal token\n";
    print "\t-o org or project owner\n";
    print "\t-r repo\n";
    print "\t-p https proxy\n";
    print "\t-s issue state: open, closed. fetch all issues if not specified";
    print "\n";
    exit 1;
}

sub validate_option {
    my @required_options = qw(o r t);
    my $option = shift;
    foreach (@required_options) {
        if (not defined $option->{$_}) {
            print "Option error: -$_ is required\n";
            usage();
        }
    }
    1;
}

sub get_issues_by_state {
    my ($ua, $url, $state) = @_;
    my $page = 1;
    my $last_page = 1;
    my @issues;
    while ($page <= $last_page) {
        $url->query_form('state'=>$state, 'page'=>$page);
        print "Fetching $state issues $url - ";
        my $resp = $ua->get($url);

        if ($resp->is_success) {
            print "done\n";
        } else {
            print "fail\n\nResponse:\n", $resp->decoded_content, "\n";
            exit 1;
        }
        my $issue = parse_json($resp->content);
        foreach (@$issue) {
            next if defined $_->{'pull_request'};
            push @issues, $_;
        }
        if ($last_page eq 1) {
            $last_page = $1 if $resp->headers->{'link'}=~/page=(\d+)>; rel="last"/
        }
        $page += 1;
    }
    return \@issues;
}

sub get_open_issues {
    my ($ua, $url) = @_;
    return get_issues_by_state($ua, $url, 'open');
}

sub get_closed_issues {
    my ($ua, $url) = @_;
    return get_issues_by_state($ua, $url, 'closed');
}

sub get_all_issues {
    my ($ua, $url) = @_;
    my @issues;
    my $open_issues = get_open_issues($ua, $url);
    my $closed_issues = get_closed_issues($ua, $url);
    push @issues, @$open_issues;
    push @issues, @$closed_issues;
    return \@issues;
}

sub format_issue {
    my $issue = shift;
    my $created_at = $1 if $issue->{'created_at'} =~ /(\d{4}-\d{2}-\d{2})/;
    my $closed_at = '';
    if (defined $issue->{'closed_at'}) {
        $closed_at = $1 if $issue->{'closed_at'} =~ /(\d{4}-\d{2}-\d{2})/;
    }

    # escape quote
    my $title = $issue->{'title'};
    $title =~ s/"/'/g;

    my $assignee = '';
    $assignee = $issue->{'assignee'}->{'login'} if defined $issue->{'assignee'};
    my $author = $issue->{'user'}->{'login'};
    my $milestone = '';
    $milestone = $issue->{'milestone'}->{'title'} if defined $issue->{'milestone'};

    # label
    my $label = join(' | ', map {$_->{'name'}} @{$issue->{'labels'}});

    return "$issue->{'number'},\"$title\",$label,$assignee,$issue->{'state'},$milestone,$author,$created_at,$closed_at";
}


my %option;
getopts('o:r:t:p:s:', \%option) or usage();
validate_option(\%option);

my $org = $option{'o'};
my $repo = $option{'r'};
my $token = $option{'t'};
my $proxy = '';
my $state = '';
$proxy = $option{'p'} if defined $option{'p'};
$state = $option{'s'} if defined $option{'s'};
if (defined $option{'s'}) {
    if ($option{'s'} =~ /^(open|closed)$/i) {
        $state = $1;
    } else {
        print "state should be open or closed.\n";
        usage();
    }
}

my $url_issues = URI->new("https://api.github.com/repos/$org/$repo/issues");
my $headers = HTTP::Headers->new('User-Agent'=>'no-one',Accept=>'application/json',Authorization=>"token $token");
my $ua = LWP::UserAgent->new;
$ua->proxy(['https'], $proxy) if $proxy;
$ua->default_headers($headers);

my $issues;
if ($state) {
    $issues = get_issues_by_state($ua, $url_issues, $state);
} else {
   $issues = get_all_issues($ua, $url_issues); 
}


print "\nnumber, title, label, assignee, state, milestone, author, created_at, closed_at\n";

foreach (@$issues) {
    my $issue = format_issue($_);
    print "$issue\n";
}

undef $issues;

