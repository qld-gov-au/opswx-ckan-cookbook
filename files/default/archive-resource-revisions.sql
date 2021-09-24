insert into resource_revision_archive (
  select * from resource_revision
  where expired_timestamp < current_date - 30
    and package_id in
      (select p.id
        from resource r
        join package p on p.id = r.package_id
        join package_extra pe on p.id = pe.package_id
       where p.state = 'active'
        and pe.state = 'active'
        and pe.key = 'update_frequency'
        and pe.value in ('near-realtime', 'hourly')
      )
);

delete from resource_revision
  where expired_timestamp < current_date - 30
    and package_id in
      (select p.id
        from resource r
        join package p on p.id = r.package_id
        join package_extra pe on p.id = pe.package_id
       where p.state = 'active'
        and pe.state = 'active'
        and pe.key = 'update_frequency'
        and pe.value in ('near-realtime', 'hourly')
      );

insert into resource_revision_archive (
  select * from resource_revision
  where expired_timestamp < current_date - 90
    and package_id in
      (select p.id
        from resource r
        join package p on p.id = r.package_id
        join package_extra pe on p.id = pe.package_id
       where p.state = 'active'
        and pe.state = 'active'
        and pe.key = 'update_frequency'
        and pe.value not in ('near-realtime', 'hourly')
      )
);

delete from resource_revision
  where expired_timestamp < current_date - 90
    and package_id in
      (select p.id
        from resource r
        join package p on p.id = r.package_id
        join package_extra pe on p.id = pe.package_id
       where p.state = 'active'
        and pe.state = 'active'
        and pe.key = 'update_frequency'
        and pe.value not in ('near-realtime', 'hourly')
      );
