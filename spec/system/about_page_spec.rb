# frozen_string_literal: true

describe "About page", type: :system do
  fab!(:current_user) { Fabricate(:user) }
  fab!(:group) { Fabricate(:group, users: [current_user]) }
  fab!(:image_upload)
  fab!(:admin) { Fabricate(:admin, last_seen_at: 1.hour.ago) }
  fab!(:moderator) { Fabricate(:moderator, last_seen_at: 1.hour.ago) }

  before do
    SiteSetting.title = "title for my forum"
    SiteSetting.site_description = "short description for my forum"
    SiteSetting.extended_site_description = <<~TEXT
      Somewhat lengthy description for my **forum**. [Some link](https://discourse.org). A list:
        1. One
        2. Two
      Last line.
    TEXT
    SiteSetting.extended_site_description_cooked =
      PrettyText.markdown(SiteSetting.extended_site_description)
    SiteSetting.about_banner_image = image_upload
    SiteSetting.contact_url = "http://some-contact-url.discourse.org"
  end

  describe "legacy version" do
    it "renders successfully for a logged-in user" do
      sign_in(current_user)

      visit("/about")

      expect(page).to have_css(".about.admins")
      expect(page).to have_css(".about.moderators")
      expect(page).to have_css(".about.stats")
      expect(page).to have_css(".about.contact")
    end

    it "renders successfully for an anonymous user" do
      visit("/about")

      expect(page).to have_css(".about.admins")
      expect(page).to have_css(".about.moderators")
      expect(page).to have_css(".about.stats")
      expect(page).to have_css(".about.contact")
    end
  end

  describe "redesigned version" do
    let(:about_page) { PageObjects::Pages::About.new }

    before do
      SiteSetting.experimental_redesigned_about_page_groups = group.id.to_s
      sign_in(current_user)
    end

    it "renders successfully for a logged in user" do
      about_page.visit

      expect(about_page).to have_banner_image(image_upload)
      expect(about_page).to have_header_title(SiteSetting.title)
      expect(about_page).to have_short_description(SiteSetting.site_description)

      expect(about_page).to have_members_count(4, "4")
      expect(about_page).to have_admins_count(1, "1")
      expect(about_page).to have_moderators_count(1, "1")
    end

    describe "displayed site age" do
      it "says less than 1 month if the site is less than 1 month old" do
        Discourse.stubs(:site_creation_date).returns(1.week.ago)

        about_page.visit

        expect(about_page).to have_site_created_less_than_1_month_ago
      end

      it "says how many months old the site is if the site is less than 1 year old" do
        Discourse.stubs(:site_creation_date).returns(2.months.ago)

        about_page.visit

        expect(about_page).to have_site_created_in_months_ago(2)
      end

      it "says how many years old the site is if the site is more than 1 year old" do
        Discourse.stubs(:site_creation_date).returns(5.years.ago)

        about_page.visit

        expect(about_page).to have_site_created_in_years_ago(5)
      end
    end

    describe "the site activity section" do
      describe "topics" do
        before do
          Fabricate(:topic, created_at: 2.days.ago)
          Fabricate(:topic, created_at: 3.days.ago)
          Fabricate(:topic, created_at: 8.days.ago)
        end

        it "shows the count of topics created in the last 7 days" do
          about_page.visit
          expect(about_page.site_activities.topics).to have_count(2, "2")
          expect(about_page.site_activities.topics).to have_7_days_period
        end
      end

      describe "posts" do
        before do
          Fabricate(:post, created_at: 2.days.ago)
          Fabricate(:post, created_at: 1.hour.ago)
          Fabricate(:post, created_at: 3.hours.ago)
          Fabricate(:post, created_at: 23.hours.ago)
        end

        it "shows the count of topics created in the last day" do
          about_page.visit
          expect(about_page.site_activities.posts).to have_count(3, "3")
          expect(about_page.site_activities.posts).to have_1_day_period
        end
      end

      describe "active users" do
        before do
          User.update_all(last_seen_at: 1.month.ago)

          Fabricate(:user, last_seen_at: 1.hour.ago)
          Fabricate(:user, last_seen_at: 1.day.ago)
          Fabricate(:user, last_seen_at: 3.days.ago)
          Fabricate(:user, last_seen_at: 6.days.ago)
          Fabricate(:user, last_seen_at: 8.days.ago)
        end

        it "shows the count of active users in the last 7 days" do
          about_page.visit
          expect(about_page.site_activities.active_users).to have_count(5, "5") # 4 fabricated above + 1 for the current user
          expect(about_page.site_activities.active_users).to have_7_days_period
        end
      end

      describe "sign ups" do
        before do
          User.update_all(created_at: 1.month.ago)

          Fabricate(:user, created_at: 3.hours.ago)
          Fabricate(:user, created_at: 3.days.ago)
          Fabricate(:user, created_at: 8.days.ago)
        end

        it "shows the count of signups in the last 7 days" do
          about_page.visit
          expect(about_page.site_activities.sign_ups).to have_count(2, "2")
          expect(about_page.site_activities.sign_ups).to have_7_days_period
        end
      end

      describe "likes" do
        before do
          UserAction.destroy_all

          Fabricate(:user_action, created_at: 1.hour.ago, action_type: UserAction::LIKE)
          Fabricate(:user_action, created_at: 1.day.ago, action_type: UserAction::LIKE)
          Fabricate(:user_action, created_at: 1.month.ago, action_type: UserAction::LIKE)
          Fabricate(:user_action, created_at: 10.years.ago, action_type: UserAction::LIKE)
        end

        it "shows the count of likes of all time" do
          about_page.visit
          expect(about_page.site_activities.likes).to have_count(4, "4")
          expect(about_page.site_activities.likes).to have_all_time_period
        end
      end
    end

    describe "our admins section" do
      before { User.update_all(last_seen_at: 1.month.ago) }

      fab!(:admins) { Fabricate.times(12, :admin) }

      it "displays only the 10 most recently seen admins when there are more than 10 admins" do
        admins[0].update!(last_seen_at: 4.minutes.ago)
        admins[1].update!(last_seen_at: 1.minutes.ago)
        admins[2].update!(last_seen_at: 10.minutes.ago)

        about_page.visit
        expect(about_page.admins_list).to have_expand_button

        displayed_admins = about_page.admins_list.users
        expect(displayed_admins.size).to eq(10)
        expect(displayed_admins.map { |u| u[:username] }.first(3)).to eq(
          [admins[1].username, admins[0].username, admins[2].username],
        )
      end

      it "allows expanding and collapsing the list of admins" do
        about_page.visit

        displayed_admins = about_page.admins_list.users
        expect(displayed_admins.size).to eq(10)

        expect(about_page.admins_list).to be_expandable

        about_page.admins_list.expand

        expect(about_page.admins_list).to be_collapsible

        displayed_admins = about_page.admins_list.users
        expect(displayed_admins.size).to eq(13) # 12 fabricated for this spec group and 1 global

        about_page.admins_list.collapse

        expect(about_page.admins_list).to be_expandable

        displayed_admins = about_page.admins_list.users
        expect(displayed_admins.size).to eq(10)
      end

      it "doesn't show an expand/collapse button when there are fewer than 10 admins" do
        User.where(id: admins.first(7).map(&:id)).destroy_all

        about_page.visit

        displayed_admins = about_page.admins_list.users
        expect(displayed_admins.size).to eq(6)
        expect(about_page.admins_list).to have_no_expand_button
      end

      it "prioritizes names when prioritize_username_in_ux is false" do
        SiteSetting.prioritize_username_in_ux = false

        about_page.visit

        displayed_admins = about_page.admins_list.users
        admins = User.where(username: displayed_admins.map { |u| u[:username] })
        expect(displayed_admins.map { |u| u[:displayed_username] }).to contain_exactly(
          *admins.pluck(:name),
        )
        expect(displayed_admins.map { |u| u[:displayed_name] }).to contain_exactly(
          *admins.pluck(:username),
        )
      end

      it "prioritizes usernames when prioritize_username_in_ux is true" do
        SiteSetting.prioritize_username_in_ux = true

        about_page.visit

        displayed_admins = about_page.admins_list.users
        admins = User.where(username: displayed_admins.map { |u| u[:username] })
        expect(displayed_admins.map { |u| u[:displayed_username] }).to contain_exactly(
          *admins.pluck(:username),
        )
        expect(displayed_admins.map { |u| u[:displayed_name] }).to contain_exactly(
          *admins.pluck(:name),
        )
      end

      it "opens the user card when a user is clicked" do
        about_page.visit

        about_page.admins_list.users.first[:node].click
        expect(about_page).to have_css("#user-card")
      end
    end

    describe "our moderators section" do
      before { User.update_all(last_seen_at: 1.month.ago) }

      fab!(:moderators) { Fabricate.times(13, :moderator) }

      it "displays only the 10 most recently seen moderators when there are more than 10 moderators" do
        moderators[10].update!(last_seen_at: 5.hours.ago)
        moderators[3].update!(last_seen_at: 2.hours.ago)
        moderators[5].update!(last_seen_at: 13.hours.ago)

        about_page.visit
        expect(about_page.moderators_list).to have_expand_button

        displayed_mods = about_page.moderators_list.users
        expect(displayed_mods.size).to eq(10)
        expect(displayed_mods.map { |u| u[:username] }.first(3)).to eq(
          [moderators[3].username, moderators[10].username, moderators[5].username],
        )
      end

      it "allows expanding and collapsing the list of moderators" do
        about_page.visit

        displayed_mods = about_page.moderators_list.users
        expect(displayed_mods.size).to eq(10)

        expect(about_page.moderators_list).to be_expandable

        about_page.moderators_list.expand

        expect(about_page.moderators_list).to be_collapsible

        displayed_mods = about_page.moderators_list.users
        expect(displayed_mods.size).to eq(14) # 13 fabricated for this spec group and 1 global

        about_page.moderators_list.collapse

        expect(about_page.moderators_list).to be_expandable

        displayed_mods = about_page.moderators_list.users
        expect(displayed_mods.size).to eq(10)
      end

      it "doesn't show an expand/collapse button when there are fewer than 10 moderators" do
        User.where(id: moderators.first(10).map(&:id)).destroy_all

        about_page.visit

        displayed_mods = about_page.moderators_list.users
        expect(displayed_mods.size).to eq(4)
        expect(about_page.moderators_list).to have_no_expand_button
      end

      it "prioritizes names when prioritize_username_in_ux is false" do
        SiteSetting.prioritize_username_in_ux = false

        about_page.visit

        displayed_mods = about_page.moderators_list.users
        moderators = User.where(username: displayed_mods.map { |u| u[:username] })
        expect(displayed_mods.map { |u| u[:displayed_username] }).to contain_exactly(
          *moderators.pluck(:name),
        )
        expect(displayed_mods.map { |u| u[:displayed_name] }).to contain_exactly(
          *moderators.pluck(:username),
        )
      end

      it "prioritizes usernames when prioritize_username_in_ux is true" do
        SiteSetting.prioritize_username_in_ux = true

        about_page.visit

        displayed_mods = about_page.moderators_list.users
        moderators = User.where(username: displayed_mods.map { |u| u[:username] })
        expect(displayed_mods.map { |u| u[:displayed_username] }).to contain_exactly(
          *moderators.pluck(:username),
        )
        expect(displayed_mods.map { |u| u[:displayed_name] }).to contain_exactly(
          *moderators.pluck(:name),
        )
      end

      it "opens the user card when a user is clicked" do
        about_page.visit

        about_page.moderators_list.users.last[:node].click
        expect(about_page).to have_css("#user-card")
      end
    end
  end
end
