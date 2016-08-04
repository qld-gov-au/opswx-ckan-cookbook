# opswx-ckan-cookbook

Author: shane.davis@linkdigital.com.au

Copyright 2016 Datashades 

**Datashades OpsWorks Cookbook.**

**Features:**

* Single click Enterprise grade CKAN deployment
* HA DB, Solr and Web nodes.
* AWS RDS for Postgres

Please see https://github.com/DataShades/ckan-aws-templates/blob/master/README.md for a broader understanding of
how this cookbook should be used.

Even without the OpsWorks stack, it's anticipated that the recipes alone should provide great insights into deploying
a highly available, scalable CKAN stack. Given that OpsWorks uses Chef Ruby scripts, it wouldn't be overly difficult to
port the cookbook to Ansible or Puppet.

**Assumptions:**

The single biggest assumption of these recipes is that you're provisioning AWS Linux AMIs. Whereas we're accutely aware
there are many Ubuntu, and other distro fans out there, I personally made a deliberate design choice to implement this
project in more of a "Cupertino" ,fixed hardware, fixed software, that just works (mostly) type of approach. That versus the
arguely more "Redmond" approach of lets try to cater for everyone, and in so doing have a less than stella hit rate.

In far more practical terms, keeping things as simple as possible makes them far more readable, adaptable and maintainable over the long term.
I fully accept more than a few might totally disagree with this approach, but that's why we build and improve.

**IMPORTANT**

This is a somewhat premature release with known issues we're working on. Based on the numerous issues discussed in 
the CKAN dev mailing list (https://lists.okfn.org/mailman/listinfo/ckan-dev) however, we felt the recipes even as they are serve a higher good
to the community as an extra reference, than sitting in our private repo.

Our hope and expectation is that it benefits the wider Public Data community and progresses the Open Data ideal.