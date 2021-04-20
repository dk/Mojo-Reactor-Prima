use ExtUtils::MakeMaker;
WriteMakefile(
        NAME           => 'Mojo::Reactor::Prima',
        AUTHOR         => 'Dmitry Karasik <dmitry@karasik.eu.org>',
        ABSTRACT_FROM  => 'Prima.pm',
        VERSION_FROM   => 'Prima.pm',
        PREREQ_PM      => { 'Mojo::Reactor' => 0, Prima => 0 },
        META_MERGE     => {
                resources => {
                        repository => 'http://github.com/dk/Mojo-Reactor-Prima'
                },
        },
);
