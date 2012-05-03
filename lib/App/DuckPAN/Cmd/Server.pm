package App::DuckPAN::Cmd::Server;

use Moo;
with qw( App::DuckPAN::Cmd );

use MooX::Options;
use Plack::Runner;
use App::DuckPAN::Web;
use File::ShareDir::ProjectDistDir;
use File::Copy;
use Path::Class;
use IO::All -utf8;
use LWP::Simple;
use HTML::TreeBuilder;

sub run {
	my ( $self, @args ) = @_;

	dir($self->app->cfg->cache_path)->mkpath unless -d $self->app->cfg->cache_path;

	copy(file(dist_dir('App-DuckPAN'),'page_root.html'),file($self->app->cfg->cache_path,'page_root.html')) unless -f file($self->app->cfg->cache_path,'page_root.html');
	copy(file(dist_dir('App-DuckPAN'),'page_spice.html'),file($self->app->cfg->cache_path,'page_spice.html')) unless -f file($self->app->cfg->cache_path,'page_share.html');
	copy(file(dist_dir('App-DuckPAN'),'page.css'),file($self->app->cfg->cache_path,'page.css')) unless -f file($self->app->cfg->cache_path,'page.css');

	my @blocks = @{$self->app->ddg->get_blocks_from_current_dir(@args)};

	print "\n\nTrying to fetch current versions of the HTML from http://duckduckgo.com/\n\n";

	my $fetch_page_root;
	if ($fetch_page_root = get('http://duckduckgo.com/')) {
		io(file($self->app->cfg->cache_path,'page_root.html'))->print($self->change_html($fetch_page_root));
	} else {
		print "\nRoot fetching failed, will just use cached version..."
	}

	my $fetch_page_spice;
	if ($fetch_page_spice = get('http://duckduckgo.com/?q=duckduckhack-template-for-spice')) {
		io(file($self->app->cfg->cache_path,'page_spice.html'))->print($self->change_html($fetch_page_spice));
	} else {
		print "\nSpice-Template fetching failed, will just use cached version..."
	}

	my $fetch_page_css;
	if ($fetch_page_css = get('http://duckduckgo.com/style.css')) {
		io(file($self->app->cfg->cache_path,'page.css'))->print($self->change_css($fetch_page_css));
	} else {
		print "\nCSS fetching failed, will just use cached version..."
	}

	my $page_root = io(file($self->app->cfg->cache_path,'page_root.html'))->slurp;
	my $page_spice = io(file($self->app->cfg->cache_path,'page_spice.html'))->slurp;
	my $page_css = io(file($self->app->cfg->cache_path,'page.css'))->slurp;

	print "\n\nStarting up webserver...";
	print "\n\nYou can stop the webserver with Ctrl-C";
	print "\n\n";

	my $web = App::DuckPAN::Web->new(
		blocks => \@blocks,
		page_root => $page_root,
		page_spice => $page_spice,
		page_css => $page_css,
	);
	my $runner = Plack::Runner->new(
		loader => 'Restarter',
		includes => ['lib'],
		app => sub { $web->run_psgi(@_) },
	);
	$runner->loader->watch("./lib");
	exit $runner->run;
}

sub change_css {
	my ( $self, $css ) = @_;
	$css =~ s!url\(("?)!url\($1http://duckduckgo.com/!g;
	return $css;
}

sub change_html {
	my ( $self, $html ) = @_;

	my $root = HTML::TreeBuilder->new;
	$root->parse($html);

	my @a = $root->look_down(
		"_tag", "a"
	);

	my @link = $root->look_down(
		"_tag", "link"
	);

	for (@a,@link) {
		if ($_->attr('type') && $_->attr('type') eq 'text/css') {
			$_->attr('href','/?duckduckhack_css=1');
		} elsif (substr($_->attr('href'),0,1) eq '/') {
			$_->attr('href','https://duckduckgo.com'.$_->attr('href'));
		}
	}

	my @script = $root->look_down(
		"_tag", "script"
	);

	for (@script) {
		if ($_->attr('src') && substr($_->attr('src'),0,1) eq '/') {
			$_->attr('src','https://duckduckgo.com'.$_->attr('src'));
		}
	}

	return $self->change_css($root->as_HTML);
}

1;
