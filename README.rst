=======
Drizzle
=======

A Lightweight SQL Database for Cloud and Web

.. epigraph::

  What, this again?

Drizzle is a community-driven open source project that is forked from the
popular MySQL database.

The Drizzle team has removed non-essential code, re-factored the remaining
code and modernized the code base moving to C++.

Charter
=======

* A database optimized for Cloud infrastructure and Web applications
* Design for massive concurrency on modern multi-cpu architecture
* Optimize memory for increased performance and parallelism
* Open source, open community, open design
* Container-first approach

Scope
=====

* Re-designed modular architecture providing plugins with defined APIs
* Simple design for ease of use and administration
* Reliable, ACID transactional

Compiling from source
=====================

Just build the container::

    podman build .

Yes, docker works too, don't be silly. But I love rootless podman myself.

Dependencies
------------

The dependencies are listed in ``bindep.txt`` to be used with either ``bindep``
or ``bindep-rs``. The Dockerfile uses ``bindep-rs`` to avoid polluting the
dependency list.

Compiling
---------

::

    autoreconf -i
    ./configure && make && make test

But seriously, just build the container. The chances this builds TODAY on your
laptop are pretty much none, as we're still forward-porting from Ubuntu Precise.

Running Drizzle
---------------

Just run the container!

Fun story - every config value in Drizzle is settable via env vars which is
how all the fancy container people like it. Been that way since 2008. What's
old is new again.

Cheers!

  - The Drizzle team
