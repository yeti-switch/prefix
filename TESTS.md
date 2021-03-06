# Tests

This document present some ways to test the [README.md](README.md)
PostgreSQL module, which aims to speed-up longest prefix searches.

## Preparing

The `prefixes.sql` creates a table which fits `prefixes.fr.csv`
content. This file contains all the official French Telephony prefixes
used as of early 2008, as found on the
[French telecom regulation authority](http://www.art-telecom.fr/)
website (see http://www.art-telecom.fr/fileadmin/wopnum.rtf).

    create table prefixes (
           prefix    text primary key,
           name      text not null,
           shortname text,
           state     char default 'S',

           check( state in ('S', 'R') )
    );
    comment on column prefixes.state is 'S:   - R: reserved';
    
    \copy prefixes from 'prefixes.fr.csv' with delimiter ';' csv quote '"'

## Creating the prefix_range table

We create the `ranges` table from the previous `prefixes` one, allowing to
quickly have data again after reinstalling the `prefix.sql` module.

    drop table ranges;
    create table ranges as select prefix::prefix_range, name, shortname, state from prefixes ;
    create index idx_prefix on ranges using gist(prefix gist_prefix_range_ops);

## Using Gevel to inspect the index

For information about the Gevel project, see
http://www.sai.msu.su/~megera/oddmuse/index.cgi/Gevel and
http://www.sigaev.ru/cvsweb/cvsweb.cgi/gevel/.

    dim=# select gist_stat('idx_prefix');
                    gist_stat
    -----------------------------------------
     Number of levels:          2
     Number of pages:           71
     Number of leaf pages:      70
     Number of tuples:          12036
     Number of invalid tuples:  0
     Number of leaf tuples:     11966
     Total size of tuples:      335728 bytes
     Total size of leaf tuples: 334056 bytes
     Total size of index:       581632 bytes

    select * from gist_print('idx_prefix') as t(level int, valid bool, a prefix_range) where level =1;
    select * from gist_print('idx_prefix') as t(level int, valid bool, a prefix_range) order by level;

## Testing the index content

Those queries should return the same line, but it fails with
`enable_seqscan to off` when the index is not properly build.

    set enable_seqscan to on;
    select * from ranges where prefix @> '0146640123';
    select * from ranges where prefix @> '0100091234';

    set enable_seqscan to off;
    select * from ranges where prefix @> '0146640123';
    select * from ranges where prefix @> '0100091234';

## Testing prefix_range GiST penalty code

We want `gpr_penalty` result to be the lower when its second argument
is the nearest of the first.

    select a, b, pr_penalty(a::prefix_range, b::prefix_range)
      from (values('095[4-5]', '0[8-9]'),
                  ('095[4-5]', '0[0-9]'),
		('095[4-5]', '[0-3]'), 
		('095[4-5]', '0'), 
		('095[4-5]', '[0-9]'), 
		('095[4-5]', '0[1-5]'), 
		('095[4-5]', '32'), 
		('095[4-5]', '[1-3]')) as t(a, b) 
    order by 3 asc;

        a     |   b    | gpr_penalty
    ----------+--------+-------------
     095[4-5] | 0[8-9] | 1.52588e-05
     095[4-5] | 0[0-9] | 1.52588e-05
     095[4-5] | [0-3]  |  0.00390625
     095[4-5] | 0      |  0.00390625
     095[4-5] | [0-9]  |  0.00390625
     095[4-5] | 0[1-5] |   0.0078125
     095[4-5] | 32     |           1
     095[4-5] | [1-3]  |           1
    (8 rows)

## Stress testing the index in an inner loop

We create a big telephone numbers table (with random entries) this way:

    create table numbers(number text primary key);
    
    insert into numbers 
      select '01' || to_char((random()*100)::int, 'FM09')
                  || to_char((random()*100)::int, 'FM09')
                  || to_char((random()*100)::int, 'FM09')
                  || to_char((random()*100)::int, 'FM09')
       from generate_series(1, 5000);  
    INSERT 0 5000

Repeat the step to obtain some more numbers, then:

    dim=# explain analyze select * from numbers n join ranges r on r.prefix @> n.number;
                                                                 QUERY PLAN
    -------------------------------------------------------------------------------------------------------------------------------------
     Nested Loop  (cost=0.00..4868614.00 rows=149575000 width=45) (actual time=0.345..4994.296 rows=10213 loops=1)
       ->  Seq Scan on numbers n  (cost=0.00..375.00 rows=25000 width=11) (actual time=0.015..12.917 rows=25000 loops=1)
       ->  Index Scan using idx_prefix on ranges r  (cost=0.00..104.98 rows=5983 width=34) (actual time=0.182..0.197 rows=0 loops=25000)
             Index Cond: (r.prefix @> (n.number)::prefix_range)
     Total runtime: 4998.936 ms
    (5 rows)


