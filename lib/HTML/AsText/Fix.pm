package HTML::AsText::Fix;
# ABSTRACT: extends HTML::Element::as_text() to render text properly

use strict;

use HTML::Tree;
use Monkey::Patch qw(:all);

# VERSION

=for test_synopsis
my ($html);

=head1 SYNOPSIS

# fix individual objects
    my $tree = HTML::TreeBuilder::XPath->new_from_content($html);
    my $guard = HTML::AsText::Fix::object($tree);

# fix deeply nested objects
    use URI;
    use Web::Scraper;

    # First, create your scraper block
    my $tweets = scraper {
        process "li.status", "tweets[]" => scraper {
            process ".entry-content", body => 'TEXT';
            process ".entry-date", when => 'TEXT';
            process 'a[rel="bookmark"]', link => '@href';
        };
    };

    my $res;
    {
        my $guard = HTML::AsText::Fix::global();
        $res = $tweets->scrape( URI->new("http://twitter.com/creaktive") );
    }

=head1 DESCRIPTION

Consider the following HTML sample:

    <p>
        <span>AAA</span>
        BBB
    </p>
    <h2>CCC</h2>
    DDD
    <br>
    EEE

C<HTML::Element::as_text()> method stringifies it as I<AAABBBCCCDDDEEE>.
Despite being correct, this is far from the actual renderization within a "real" browser.
L<links(1)>, L<lynx(1)> & L<w3m(1)> break lines this way:

    AAABBB
    CCC
    DDD
    EEE

This module tries to implement the same behavior in the method L<HTML::Element/as_text>.
By default, C<$/> value is inserted in place of line breaks, and C<"\x{200b}"> (Unicode zero-width space) separates text from adjacent inline elements.

=head2 Distinction between block/inline nodes

"span", for instance, is an inline node:

    <p><span>A</span>pple</p>

In that case, there really shouldn't be a space between "A" and "pple".
To handle inline nodes properly, only block nodes are separated by line break.
Following nodes are currently assumed being blocks:

=for :list
* p
* h1 h2 h3 h4 h5 h6
* dl dt dd
* ol ul li
* dir
* address
* blockquote
* center
* del
* div
* hr
* ins
* noscript script
* pre
* br (just to make sense)

(source: L<http://en.wikipedia.org/wiki/HTML_element#Block_elements>)

=cut

my $block_tags = {
    map { $_ => 1 } qw(
        p
        h1 h2 h3 h4 h5 h6
        dl dt dd
        ol ul li
        dir
        address
        blockquote
        center
        del
        div
        hr
        ins
        noscript script
        pre
    )
};

my $nillio = [];

=func as_text

The replacement function.
Not to be used separately.
It is injected inside L<HTML::Element>.

=cut

sub as_text {

    # Yet another iteratively implemented traverser
    my ( $this, %options ) = @_;
    my $skip_dels = $options{'skip_dels'} || 0;
    my $lf = defined( $options{'lf_char'} )
        ? $options{'lf_char'}
        : $/;
    my $zwsp = defined( $options{'zwsp_char'} )
        ? $options{'zwsp_char'}
        : "\x{200b}";                    # zero-width space (ZWSP)

    my (@pile) = ($this);
    my $tag;
    my $text = '';
    while (@pile) {
        if ( !defined( $pile[0] ) ) {    # undef!
                                         # no-op
        }
        elsif ( !ref( $pile[0] ) ) {     # text bit!  save it!
            $text .= shift @pile;
        }
        else {                           # it's a ref -- traverse under it
            $this = shift @pile;
            $tag = $this->{'_tag'};
            my @rest = @{ $this->{'_content'} || $nillio };

            if ( exists $block_tags->{$tag} ) {
                push @rest, $lf;
            }
            elsif ( $tag eq 'br' ) {
                push @rest, $lf;
            }
            else {
                push @rest, $zwsp;
            }

            unshift @pile, @rest
                unless $tag eq 'style'
                    or $tag eq 'script'
                    or ( $skip_dels and $tag eq 'del' );
        }
    }

    if ( $options{'trim'} ) {
        my $extra_chars = $options{'extra_chars'} || '';
        $text =~ s/[\n\r\f\t\x{a0}$extra_chars ]+$//s;
        $text =~ s/^[\n\r\f\t\x{a0}$extra_chars ]+//s;
        $text =~ s/[\x{a0}$extra_chars ]/ /g;
    }

    return $text;
}

=func global

Hook into every L<HTML::Element> within the lexical scope.
Returns the guard object, destroying it will unhook safely.

Accepts following options:

=for :list
* B<lf_char>: character inserted between block nodes (by default, C<$/>);
* B<zwsp_char>: character inserted between inline nodes (by default, C<"\x{200b}">, Unicode zero-width space);
* B<trim>: trim heading/trailing spaces (considers C<"\x{A0}"> as space!);
* B<extra_chars>: extra characters to trim;
* B<skip_dels>: if true, then text content under "del" nodes is not included in what's returned.

For example, to completely get rid of separation between inline nodes:

    my $guard = HTML::AsText::Fix::global(zwsp_char => '');

=cut

sub global {
    my ( %options ) = @_;
    patch_package 'HTML::Element', as_text => sub {
        shift; # $original
        as_text( @_, %options );
    };
}

=func object

Hook object instance.
Accepts the same options as L</global>:

    my $guard = HTML::AsText::Fix::object($tree, zwsp_char => '');

=cut

sub object {
    my ( $obj, %options ) = @_;
    patch_object $obj, as_text => sub {
        shift; # $original
        my $self = shift;
        as_text( $self, @_, %options );
    };
}

=head1 SEE ALSO

=for :list
* L<HTML::Element>
* L<HTML::Tree>
* L<HTML::FormatText>
* L<Monkey::Patch>

=head1 ACKNOWLEDGEMENTS

=for :list
* L<Αριστοτέλης Παγκαλτζής|https://metacpan.org/author/ARISTOTLE>
* L<Toby Inkster|https://metacpan.org/author/TOBYINK>

=cut

1;
