# Migrate the widget model from application/models/widget to WidgetBundle

**Type:** feature
**Asked:** Plan the widget model migration from application/models/widget to lib.

## Summary

Move the `models\widget` family (Widget, Gadget, WidgetMapper, GadgetMapper) to a new `WidgetBundle` under `lib/`.

The migration has two independent workstreams:

1. **Move** the classes verbatim, then flip consumers.
2. **Split** each mapper into a query builder and a persister.

## Acceptance criteria

- [ ] All classes moved to `WidgetBundle` verbatim
- [ ] `grep -r 'models\\widget' application` outside lib is empty

## Steps

Step 1. [x] Create WidgetBundle scaffold — Create WidgetBundle scaffold
- **Create:** `application/lib/WidgetBundle/WidgetBundle.php`, `application/lib/WidgetBundle/Entity/widget.php`
- **Modify:** none (scaffold only)
- **Test:** `docker compose exec -T fpm ./phpunit`
- **Check:** `wc -l application/lib/WidgetBundle/*`

Step 2. [ ] Move Entity + Mapper files (Widget)
- **Create:** `application/lib/WidgetBundle/Entity/Widget.php`, `application/lib/WidgetBundle/Mapper/WidgetMapper.php`
- **Modify:** none (copy to new paths, rename namespace)
- **Test:** `docker compose exec -T fpm ./phpunit`
- **Check:** Rename-similarity diff shows 0 content changes

Step 3. [ ] Add class_alias bridges + delete old classes
- **Create:** none
- **Modify:** `application/models/widget/Widget.php`, `application/models/widget/WidgetMapper.php`
- **Test:** `docker compose exec -T fpm ./phpunit`
- **Check:** `php -l` on each bridge file

Step 4. [ ] Flip consumers to the bundle namespace
- **Create:** none
- **Modify:** `application/lib/LegacyBundle/LegacyBundle.php`, `application/events/Init.php`
- **Test:** `docker compose exec -T fpm ./phpunit`
- **Check:** `grep -r 'models\\widget' application --include='*.php' | grep -v lib/WidgetBundle` is empty
