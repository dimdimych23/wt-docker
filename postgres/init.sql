CREATE SCHEMA IF NOT EXISTS dbo;
ALTER SCHEMA dbo OWNER TO wt;

CREATE OR REPLACE FUNCTION dbo.count_rows(schema text, tablename text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
  result integer;
  query varchar;
begin
  query := 'SELECT count(1) FROM ' || schema || '.' || tablename;
  execute query into result;
  return result;
end;
$$;
ALTER FUNCTION dbo.count_rows(schema text, tablename text) OWNER TO wt;

CREATE OR REPLACE FUNCTION dbo.fn_loadobjecturl(schema character varying, id bigint, is_deleted integer DEFAULT NULL::integer) RETURNS TABLE(data text, created timestamp without time zone, modified timestamp without time zone)
    LANGUAGE plpgsql
    AS $$
declare 
form varchar(256);
sql text;
is_obj_deleted int4;
begin
	
sql := format('select form,is_deleted,modified from %s."(spxml_objects)" where id=%s;',schema,id);

execute sql into form,is_obj_deleted,modified;

if form is not null and (is_obj_deleted is null or is_deleted=is_obj_deleted) then
	
sql := format('select cast(data as text),created,modified from %s."%s" where id=%s;',schema,form,id);
  
return query execute sql;

end if;
  
exception when others then 
 raise;
end;
$$;
ALTER FUNCTION dbo.fn_loadobjecturl(schema character varying, id bigint, is_deleted integer) OWNER TO wt;

CREATE OR REPLACE FUNCTION dbo.getdbversion() RETURNS character varying
    LANGUAGE plpgsql
    AS $$

BEGIN
	return '1.22.12.28';
END;

$$;
ALTER FUNCTION dbo.getdbversion() OWNER TO wt;

CREATE OR REPLACE FUNCTION dbo.object_id(obj_name text) RETURNS oid
    LANGUAGE plpgsql STABLE STRICT
    AS $$
begin
  if obj_name like '%(%)' then --имя функции с прототипом
    begin
      return obj_name::regprocedure::oid;
    exception when undefined_function then return null;
    end;
  end if;
  --для одноименной таблицы и функции без прототипа будет выдан oid таблицы!!!
  begin
    return obj_name::regclass::oid;
  exception when undefined_table then null;
  end;
  begin
    return obj_name::regproc::oid;
  exception
    when undefined_function then null;
    when ambiguous_function then
      --для перегруженной функции возвращаем oid первой попавшейся
      --СХЕМА НЕ УЧИТЫВАЕТСЯ!!!
      raise warning '%', SQLERRM;
      return oid from pg_proc where proname=obj_name limit 1;
  end;
  return null;
end;
$$;
ALTER FUNCTION dbo.object_id(obj_name text) OWNER TO wt;

CREATE OR REPLACE FUNCTION dbo.object_name(obj_id oid) RETURNS name
    LANGUAGE plpgsql STABLE STRICT
    AS $$
begin
  return coalesce(
   (select relname from pg_class where oid=$1),
   (select proname from pg_proc where oid=$1)
  );
end;
$$;
ALTER FUNCTION dbo.object_name(obj_id oid) OWNER TO wt;

CREATE OR REPLACE FUNCTION dbo.spxml_check_db() RETURNS integer
    LANGUAGE plpgsql
    AS $$

DECLARE ok INTEGER;
BEGIN
    
    ok:=0;
    
     select count(*) into ok from information_schema.tables
where
table_schema='dbo'
and table_name in ('(spxml_blobs)',
'(spxml_foreign_arrays)',
'(spxml_metadata)',
'(spxml_objects)');
  
if (ok<4) then
  return 0;
end if;
    
ok=1;
    
RETURN ok;
end;

$$;
ALTER FUNCTION dbo.spxml_check_db() OWNER TO wt;

CREATE OR REPLACE FUNCTION dbo.spxml_check_db(schema character varying) RETURNS integer
    LANGUAGE plpgsql
    AS $$

DECLARE ok INTEGER;
BEGIN
    
    ok:=0;
    
     select count(*) into ok from information_schema.tables
where
table_schema=@schema
and table_name in ('(spxml_blobs)',
'(spxml_foreign_arrays)',
'(spxml_metadata)',
'(spxml_objects)');
  
if (ok<4) then
  return 0;
end if;
    
ok=1;
    
RETURN ok;
end;

$$;
ALTER FUNCTION dbo.spxml_check_db(schema character varying) OWNER TO wt;

CREATE OR REPLACE FUNCTION dbo.spxml_hash_tg() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

BEGIN
    IF tg_op = 'INSERT' OR tg_op = 'UPDATE' THEN
    	NEW.ext = substring(NEW.url from '\.([^\.]*)$');        
    	if NEW.data is not null then
        	NEW.hashdata = md5(NEW.data);
         end if;
        RETURN NEW;
    END IF;
END;

$$;
ALTER FUNCTION dbo.spxml_hash_tg() OWNER TO wt;

CREATE or replace FUNCTION dbo.str_contains(l1 text, l2 text)
 RETURNS boolean
 LANGUAGE plpgsql
AS $$
begin
	
if (pg_catalog.strpos(l1,l2)<=0) then
	return false;
end if;

return true;
end;

$$;
ALTER FUNCTION dbo.str_contains(l1 text, l2 text) OWNER TO wt;

CREATE TABLE IF NOT EXISTS dbo."(ft_last_index)" (
	id int4 NOT NULL,
	last_ft_index_date timestamp NOT NULL,
	CONSTRAINT "PK_(ft_last_index)" PRIMARY KEY (id)
) TABLESPACE pg_default;
ALTER TABLE dbo."(ft_last_index)" OWNER TO wt;

CREATE TABLE IF NOT EXISTS dbo."(spxml_blobs)" (
	url varchar(256) NOT NULL,
	"data" bytea NULL,
	ext varchar(256) NULL,
	created timestamp NULL,
	modified timestamp NULL,
	hashdata varchar(160) NULL,
	CONSTRAINT "(spxml_blobs)_PK" PRIMARY KEY (url)
) TABLESPACE pg_default;
ALTER TABLE dbo."(spxml_blobs)" OWNER TO wt;

DROP TRIGGER IF EXISTS spxml_ext_tr on dbo."(spxml_blobs)";
create trigger spxml_ext_tr before insert
or update on
dbo."(spxml_blobs)" for each row execute procedure dbo.spxml_hash_tg();

CREATE TABLE IF NOT EXISTS dbo."(spxml_foreign_arrays)" (
	"catalog" varchar(64) NOT NULL,
	catalog_elem varchar(64) NOT NULL,
	name varchar(64) NOT NULL,
	foreign_array varchar(96) NOT NULL,
	CONSTRAINT "PK_(spxml_foreign_arrays)_1" PRIMARY KEY (catalog, catalog_elem, name)
) TABLESPACE pg_default;
ALTER TABLE dbo."(spxml_foreign_arrays)" OWNER TO wt;

CREATE TABLE IF NOT EXISTS dbo."(spxml_metadata)" (
	"schema" varchar(64) NOT NULL,
	form varchar(64) NOT NULL,
	tablename varchar(64) NULL,
	hash varchar(64) NULL,
	doc_list bool NULL,
	primary_key varchar(64) NULL,
	parent_id_elem varchar(64) NULL,
	spxml_form varchar(512) NULL,
	spxml_form_elem varchar(96) NULL,
	spxml_form_type int4 NULL,
	single_tenant int4 NULL,
	ft_idx bool NULL,
	CONSTRAINT pk_spxml_metadata PRIMARY KEY (schema, form)
) TABLESPACE pg_default;
ALTER TABLE dbo."(spxml_metadata)" OWNER TO wt;

CREATE TABLE IF NOT EXISTS dbo."(spxml_objects)" (
	id int8 NOT NULL,
	form varchar(64) NULL,
	spxml_form varchar(512) NULL,
	is_deleted int4 NULL,
	modified timestamp NULL,
	CONSTRAINT "PK_spxml_objects" PRIMARY KEY (id)
)  TABLESPACE pg_default;
ALTER TABLE dbo."(spxml_objects)" OWNER TO wt;

CREATE INDEX IF NOT EXISTS ix_del_spxml_objects ON dbo."(spxml_objects)" USING btree (is_deleted);
ALTER INDEX dbo.ix_del_spxml_objects OWNER TO wt;