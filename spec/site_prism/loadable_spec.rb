# frozen_string_literal: true

describe SitePrism::Loadable do
  let(:loadable) do
    Class.new do
      include SitePrism::Loadable
    end
  end

  class MyLoadablePage < SitePrism::Page; end

  describe '.load_validations' do
    context 'with no inheritance classes' do
      it 'returns load_validations from the current class' do
        validation1 = -> { true }
        validation2 = -> { true }

        loadable.load_validation(&validation1)
        loadable.load_validation(&validation2)

        expect(loadable.load_validations).to eq([validation1, validation2])
      end
    end

    context 'with inheritance classes' do
      it 'returns load_validations from the current and inherited classes' do
        subklass = Class.new(loadable)
        validation1 = -> { true }
        validation2 = -> { true }

        loadable.load_validation(&validation1)
        subklass.load_validation(&validation2)

        expect(subklass.load_validations).to eq([validation1, validation2])
      end

      it 'ensures that load validations of parents are checked first' do
        subklass = Class.new(loadable)
        validation1 = -> { true }
        validation2 = -> { true }
        validation3 = -> { true }
        validation4 = -> { true }
        validation5 = -> { true }

        loadable.load_validation(&validation5)
        subklass.load_validation(&validation1)
        subklass.load_validation(&validation2)
        subklass.load_validation(&validation3)
        loadable.load_validation(&validation4)

        expect(subklass.load_validations).to eq(
          [validation5, validation4, validation1, validation2, validation3]
        )
      end
    end

    context 'a standard page' do
      it 'has no default load validations' do
        expect(MyLoadablePage.load_validations.length).to eq(0)
      end
    end
  end

  describe '.load_validation' do
    it 'adds validations to the load_validations list' do
      expect { loadable.load_validation { true } }
        .to change { loadable.load_validations.size }.by(1)
    end
  end

  describe '#when_loaded' do
    it "executes and yields itself to the provided block \
when all load validations pass" do
      loadable.load_validation { true }
      instance = loadable.new

      expect(instance).to receive(:foo)

      instance.when_loaded(&:foo)
    end

    context 'with failing validations' do
      before { loadable.load_validation { [false, 'VALIDATION FAILED'] } }

      it 'raises a FailedLoadValidationError' do
        expect { loadable.new.when_loaded { :foo } }
          .to raise_error(SitePrism::FailedLoadValidationError)
      end

      it 'can be supplied with a user-defined message' do
        expect { loadable.new.when_loaded { :foo } }
          .to raise_error
          .with_message('VALIDATION FAILED')
      end
    end

    it 'raises an error immediately on the first validation failure' do
      validation_spy1 = spy(valid?: false)
      validation_spy2 = spy(valid?: false)

      loadable.load_validation { validation_spy1.valid? }
      loadable.load_validation { validation_spy2.valid? }

      expect { loadable.new.when_loaded { puts 'foo' } }
        .to raise_error(SitePrism::FailedLoadValidationError)

      expect(validation_spy1).to have_received(:valid?).once
      expect(validation_spy2).not_to have_received(:valid?)
    end

    it 'executes validations only once for nested calls' do
      james_bond = spy
      validation_spy1 = spy(valid?: true)

      loadable.load_validation { validation_spy1.valid? }
      instance = loadable.new

      instance.when_loaded do
        instance.when_loaded do
          instance.when_loaded do
            james_bond.drink_martini
          end
        end
      end

      expect(james_bond).to have_received(:drink_martini)
      expect(validation_spy1).to have_received(:valid?).once
    end

    it 'resets the loaded cache at the end of the block' do
      loadable.load_validation { true }
      instance = loadable.new

      expect(instance.loaded).to be nil

      instance.when_loaded { |i| expect(i.loaded).to be true }

      expect(instance.loaded).to be nil
    end
  end

  describe '#loaded?' do
    # We want to test with multiple inheritance
    let(:inheriting_loadable) { Class.new(loadable) }

    subject { inheriting_loadable.new }

    it 'returns true if loaded value is cached' do
      validation_spy1 = spy(valid?: true)
      loadable.load_validation { validation_spy1.valid? }
      instance = loadable.new
      instance.loaded = true

      expect(instance).to be_loaded

      expect(validation_spy1).not_to have_received(:valid?)
    end

    it 'returns true if all load validations pass' do
      loadable.load_validation { true }
      loadable.load_validation { true }
      inheriting_loadable.load_validation { true }
      inheriting_loadable.load_validation { true }

      expect(inheriting_loadable.new).to be_loaded
    end

    it 'returns false if a defined load validation fails' do
      loadable.load_validation { true }
      loadable.load_validation { true }
      inheriting_loadable.load_validation { true }
      inheriting_loadable.load_validation { false }

      expect(inheriting_loadable.new).not_to be_loaded
    end

    it 'returns false if an inherited load validation fails' do
      loadable.load_validation { true }
      loadable.load_validation { false }
      inheriting_loadable.load_validation { true }
      inheriting_loadable.load_validation { true }

      expect(inheriting_loadable.new).not_to be_loaded
    end

    it 'sets the load_error if a failing load_validation supplies one' do
      loadable.load_validation { [true, 'this cannot fail'] }
      loadable.load_validation { [false, 'fubar'] }
      inheriting_loadable.load_validation { [true, 'this also cannot fail'] }

      instance = inheriting_loadable.new
      instance.loaded?

      expect(instance.load_error).to eq('fubar')
    end

    it { is_expected.to be_loaded }
  end
end
